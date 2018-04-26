//
//  ViewController.swift
//  inspire
//
//  Created by Rob Broadwell on 4/25/18.
//  Copyright © 2018 Rob Broadwell. All rights reserved.
//

import UIKit
import CoreData

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    private let url = URL(string: "http://dev.inspiringapps.com/Files/IAChallenge/30E02AAA-B947-4D4B-8FB6-9C57C43872A9/Apache.log")!
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var progressView: UIProgressView!
    
    private var tableData: [NSManagedObject]!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.isHidden = true
        tableView.delegate = self
        tableView.dataSource = self
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        let context = appDelegate.persistentContainer.viewContext
        
        DispatchQueue.global(qos: .background).async {
            self.fetchSequences(withContext: context)
            
            DispatchQueue.main.async {
                self.loadSequences(withContext: context)
            }
        }

    }
    
    // MARK:- TableView
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let data = tableData else { return UITableViewCell() }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "SequenceCell", for: indexPath) as! SequenceCell
        let sequence = data[indexPath.row]
        
        guard let count = sequence.value(forKey: "count") as? Int,
            let path1 = sequence.value(forKey: "path_1") as? String,
            let path2 = sequence.value(forKey: "path_2") as? String,
            let path3 = sequence.value(forKey: "path_3") as? String else { return UITableViewCell() }
        
        cell.scoreLabel.text = String(describing: count)
        cell.path1Label.text = path1
        cell.path2Label.text = path2
        cell.path3Label.text = path3
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let data = tableData else { return 0 }
        return data.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 75
    }
    
    // MARK:- Networking / Data

    func fetchSequences(withContext context: NSManagedObjectContext) {
        
        // private managed object context
        let privateMOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateMOC.parent = context

        let entity = NSEntityDescription.entity(forEntityName: "Sequences", in: context)
        
        // remove anything residual from CoreData
        purgeCoreData(context: privateMOC)
        
        // tracks active sequences for each IP, example:
        // ["192.168.1.1": ["/example/"]
        // ["192.168.1.1": ["/example/", "/paths/"]
        // ["192.168.1.1": ["/example/", "/paths/", "/complete/"]
        // before pushing sequence into CoreData
        var sequences = [String: [String]]()
        
        do {
            
            // get the .log file from the server
            let html = try String(contentsOf: url, encoding: .utf8)
            
            // split it up by new lines (\n)
            let lines = html.lines
            
            // iterate through the lines of the log file
            for (index, row) in lines.enumerated() {
                
                DispatchQueue.main.async {
                    let progress = Float(index) / Float(lines.count)
                    self.progressLabel.text = "Processed \(index) of \(lines.count) records."
                    self.progressView.setProgress(progress, animated: false)
                }
                
                // split the elements apart
                let split = row.split(separator: " ")
                
                // get the ip and page
                // TODO: this works but could be better
                let ip = String(split[0])
                let path = String(split[6])
                
                // if this is the first sequence for an IP create a tracking array
                if sequences[ip] == nil {
                    sequences[ip] = [String]()
                }
                
                // add current path to sequence tracking
                sequences[ip]?.append(path)
                
                // protect against nil sequence
                guard let sequence = sequences[ip] else { return }
                
                if sequence.count == 3 {
                    
                    let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Sequences")
                    
                    // check if the sequence already exists
                    let pathPredicate1 = NSPredicate(format: "path_1 = %@", sequence[0])
                    let pathPredicate2 = NSPredicate(format: "path_2 = %@", sequence[1])
                    let pathPredicate3 = NSPredicate(format: "path_3 = %@", sequence[2])
                    let predicate = NSCompoundPredicate(type: NSCompoundPredicate.LogicalType.and, subpredicates: [pathPredicate1, pathPredicate2, pathPredicate3])
                    
                    request.predicate = predicate
                    request.returnsObjectsAsFaults = false
                    let result = try privateMOC.fetch(request)
                    
                    if result.count > 0 {
                        // this sequence already exists -> increment the count
                        for data in result as! [NSManagedObject] {
                            data.setValue(data.value(forKey: "count") as! Int + 1, forKey: "count")
                        }
                        
                    } else {
                        // this sequence is new -> create a CoreData managed object
                        let newSequence = NSManagedObject(entity: entity!, insertInto: privateMOC)
                        
                        newSequence.setValue(sequence[0], forKey: "path_1")
                        newSequence.setValue(sequence[1], forKey: "path_2")
                        newSequence.setValue(sequence[2], forKey: "path_3")
                        newSequence.setValue(1, forKey: "count")
                        
                    }
                    
                    // pop the first path from the sequence to continue tracking
                    sequences[ip]?.remove(at: 0)
                    
                }
            }
            
            try privateMOC.save()
            
        } catch {
            print("Something went wrong.")
        }
    }
    
    // MARK:- CoreData

    /// Wipes all records from CoreData.
    private func purgeCoreData(context: NSManagedObjectContext) {
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Sequences")
        request.returnsObjectsAsFaults = false
        
        do {
            let result = try context.fetch(request)
            for data in result as! [NSManagedObject] {
                context.delete(data)
            }
            try context.save()
            
        } catch {
            print("Something went wrong.")
        }
    }

    /// Loads all sequences from CoreData for the TableView.
    private func loadSequences(withContext context: NSManagedObjectContext) {

        // core data fetch request
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Sequences")
        request.sortDescriptors = [NSSortDescriptor(key: "count", ascending: false)]
        request.returnsObjectsAsFaults = false
        
        do {
            tableData = try context.fetch(request) as! [NSManagedObject]
            if self.tableData.count > 0 {
                self.tableView.reloadData()
                self.tableView.isHidden = false
            }
            
        } catch {
            print("Something went wrong.")
        }
    }
    
}

extension String {
    var lines: [String] {
        var result: [String] = []
        enumerateLines { line, _ in result.append(line) }
        return result
    }
}

