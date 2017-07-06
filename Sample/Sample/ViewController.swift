//
//  ViewController.swift
//  Sample
//
//  Created by Meniny on 2017-07-07.
//  Copyright © 2017年 Meniny. All rights reserved.
//

import UIKit
import Zipper

class ViewController: UIViewController {
    
    var documentDirectory: URL {
        let documentUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentUrl
    }
    
    let zippingDirectory = "Zipping"
    let sourceArchiveName = "archive.zip"
    let destinationDirectory = "Unzipped"

    @IBAction func zipThem(_ sender: UIButton) {
        let sourceURL = documentDirectory.appendingPathComponent(zippingDirectory)
        let zipFileURL = documentDirectory.appendingPathComponent("Zipper_\(Date().timeIntervalSince1970).zip")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("'\(sourceURL.path)' does not exists")
            return
        }
        
        guard let zip = Zipper(url: zipFileURL, accessMode: .create) else {
            print("Unable to accessing the resources")
            return
        }
        do {
            try zip.zip(item: sourceURL)
            print("Archived to: \(zip.url.path)")
        } catch let error {
            print("Error: \(error)")
        }
    }
    
    @IBAction func upzipThem(_ sender: UIButton) {
        self.unzip(to: destinationDirectory + "_\(Date().timeIntervalSince1970)")
    }
    
    func unzip(to folderName: String) {
        let destinationURL = documentDirectory.appendingPathComponent(folderName)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            print("'\(destinationURL.path)' already exists")
            return
        }
        guard let path = Bundle.main.path(forResource: sourceArchiveName, ofType: nil) else {
            print("Unable to accessing the resources")
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let zip = Zipper(url: url, accessMode: .read) else {
            print("Unable to create Zipper object")
            return
        }
        do {
            try zip.unzip(to: destinationURL)
            print("Unzipped to '\(destinationURL.path)'")
        } catch let error {
            print("Error: \(error)")
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.unzip(to: zippingDirectory)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

