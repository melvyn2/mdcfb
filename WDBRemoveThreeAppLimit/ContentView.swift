//
//  ContentView.swift
//  WDBRemoveThreeAppLimit
//
//  Created by Zhuowei Zhang on 2023-01-31.
//

import SwiftUI

// A elegant file manager for CVE-2022-446689

// Structs
struct File: Identifiable {
    var id = UUID()
    var name: String
    var type: String
    var size: String
    var date: String
}

struct Folder: Identifiable {
    var id = UUID()
    var name: String
    var contents: [File]
}

func overwriteFile(fileDataLocked: Data, pathtovictim: String) -> Bool {
    do {
        try fileDataLocked.write(to: URL.init(string: pathtovictim)!)
    } catch {
        return false
    }
    return true
}

// FileManager ListItem

struct ListItem: View {
    var file: File
    var body: some View {
        HStack {
            Image(systemName: "doc")
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading) {
                Text(file.name)
                    .font(.headline)
                Text(file.type)
                    .font(.subheadline)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(file.size)
                    .font(.subheadline)
                Text(file.date)
                    .font(.subheadline)
            }
        }
    }
}

// FileManager ContentView, begin in path "/"
// make sure the filemanagers don't overlap
struct FileManagerView: View {
    
    @State var path: String = "/"
    @State var folders: [Folder] = []
    @State var files: [File] = []
    @State var empty: Bool = false
    @State var message: String = "";

    var body: some View {
        VStack {
            HStack{
                Text(message)
                Button(action: {
                    grant_full_disk_access { error in
                        if let error = error {
                            print(error)
                            DispatchQueue.main.async {
                                message = "Failed to get full disk access: \(error)"
                            }
                            return
                        }
                        if !patch_installd() {
                          print("can't patch installd")
                          DispatchQueue.main.async {
                            message = "Failed to patch installd."
                          }
                          return
                        }
                        DispatchQueue.main.async {
                            message = "Success."
                        }
                    }
                }) {
                    Text("Go")
                }.padding(16)
            }
            List {
                ForEach(folders, id: \.id) { folder in
                    NavigationLink(destination: FileManagerView(path: path + folder.name + "/")) {
                        HStack {
                            Image(systemName: "folder")
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(folder.name)
                                .font(.headline)
                        }
                    }
                }
                ForEach(files, id: \.id) { file in
                    Button(action: {
                        // if the file is a plist, open the plist editor
                        if file.type == "plist" || file.type == "strings" {
                            let fileManager = FileManager.default
                            let data = fileManager.contents(atPath: path + file.name)
                            let plist = try! PropertyListSerialization.propertyList(from: data!, options: [], format: nil) as! [String: Any]
                            let keys = plist.keys.sorted()
                            var values: [String] = []
                            var types: [String] = []
                            for key in keys {
                                let value = plist[key]!
                                values.append("\(value)")
                                types.append("\(type(of: value))")
                            }
                            let vc = UIHostingController(rootView: PlistEditorView(path: path + file.name, plist: plist, keys: keys, values: values, types: types))
                            UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true, completion: nil)
                        } else {
                            // use TextEditor to edit the file
                            let vc = UIHostingController(rootView: TextEditorView(path: path + file.name))
                            UIApplication.shared.windows.first?.rootViewController?.present(vc, animated: true, completion: nil)
                        }
                    }) {
                        ListItem(file: file)
                    }
                }
                if empty {
                    Text("Awww, sandbox has blocked us from viewing this folder :(")
                    Text("If you know the direct path, please enter it here.")
                    Button(action: {
                        // ask user for direct path to FOLDER
                        let alert = UIAlertController(title: "Enter Direct Path", message: "Enter the direct path to the folder you want to access.", preferredStyle: .alert)
                        alert.addTextField { (textField) in
                            textField.text = path
                        }
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                        alert.addAction(UIAlertAction(title: "Enter", style: .default, handler: { (_) in
                            let text = alert.textFields![0].text!
                            if text.last != "/" {
                                path = text + "/"
                            } else {
                                path = text
                            }
                            // navigate to the new path
                            folders = []
                            files = []
                            let fileManager = FileManager.default
                            let enumerator = fileManager.enumerator(atPath: path)
                            while let element = enumerator?.nextObject() as? String {
                                // only do the top level files and folders
                                if element.contains("/") {
                                    continue
                                }
                                let attrs = try! fileManager.attributesOfItem(atPath: path + element)
                                let type = attrs[.type] as! FileAttributeType
                                if type == .typeDirectory {
                                    folders.append(Folder(name: element, contents: []))
                                } else if type == .typeRegular {
                                    let size = attrs[.size] as! UInt64
                                    let date = attrs[.modificationDate] as! Date
                                    let dateFormatter = DateFormatter()
                                    dateFormatter.dateFormat = "MMM dd, yyyy"
                                    let dateString = dateFormatter.string(from: date)
                                    let sizeString = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                                    let fileExtension = element.split(separator: ".").last!
                                    files.append(File(name: element, type: "\(fileExtension)", size: sizeString, date: dateString))
                                }
                            }
                            if folders.count == 0 && files.count == 0 {
                                empty = true
                            } else {
                                empty = false
                            }
                        }))
                        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                    }) {
                        Text("Enter Direct Path")
                    }
                }
            }
            .navigationTitle(path)
            .onAppear(perform: {
                // clear the arrays
                folders = []
                files = []
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(atPath: path)
                while let element = enumerator?.nextObject() as? String {
                    // only do the top level files and folders
                    if element.contains("/") {
                        continue
                    }
                    let attrs = try! fileManager.attributesOfItem(atPath: path + element)
                    let type = attrs[.type] as! FileAttributeType
                    if type == .typeDirectory {
                        folders.append(Folder(name: element, contents: []))
                    } else if type == .typeRegular {
                        let size = attrs[.size] as! UInt64
                        let date = attrs[.modificationDate] as! Date
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                        let dateString = formatter.string(from: date)
                        var sizeString = ""
                        if size < 1024 {
                            sizeString = "\(size) B"
                        } else if size < 1024 * 1024 {
                            sizeString = "\(size / 1024) KB"
                        } else if size < 1024 * 1024 * 1024 {
                            sizeString = "\(size / 1024 / 1024) MB"
                        } else {
                            sizeString = "\(size / 1024 / 1024 / 1024) GB"
                        }
                        files.append(File(name: element, type: element.components(separatedBy: ".").last!, size: sizeString, date: dateString))
                    }
                }
                // if they're empty, add a "no files" message in gray
                if folders.isEmpty && files.isEmpty {
                    empty = true
                }
            })
        }
    }
}

// PlistEditorView
struct PlistEditorView: View {
    @State var path: String
    @State var plist: [String: Any] = [:]
    @State var keys: [String] = []
    @State var values: [String] = []
    @State var types: [String] = []
    @State var newKey: String = ""
    @State var newValue: String = ""
    @State var newType: String = "String"
    @State var showAdd: Bool = false
    @State var showEdit: Bool = false
    @State var editIndex: Int = 0
    @State var showDelete: Bool = false
    @State var deleteIndex: Int = 0
    var body: some View {
        VStack {
            List {
                ForEach(keys.indices, id: \.self) { index in
                    HStack {
                        // check if they're in range
                        if index < keys.count && index < values.count && index < types.count {
                            Text(keys[index])
                                .font(.headline)
                            Spacer()
                            Text(values[index])
                                .font(.subheadline)
                            Text(types[index])
                                .font(.subheadline)
                        }
                    }
                    .onTapGesture {
                        showEdit = true
                        editIndex = index
                    }
                    .contextMenu {
                        Button(action: {
                            showEdit = true
                            editIndex = index
                        }) {
                            Text("Edit")
                        }
                        Button(action: {
                            showDelete = true
                            deleteIndex = index
                        }) {
                            Text("Delete")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                VStack {
                    Text("Add Key")
                        .font(.title)
                    TextField("Key", text: $newKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Value", text: $newValue)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Picker("Type", selection: $newType) {
                        Text("String").tag("String")
                        Text("Integer").tag("Integer")
                        Text("Boolean").tag("Boolean")
                        Text("Float").tag("Float")
                        Text("Double").tag("Double")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    Button(action: {
                        if newKey != "" && newValue != "" {
                            keys.append(newKey)
                            values.append(newValue)
                            types.append(newType)
                            newKey = ""
                            newValue = ""
                            newType = "String"
                            showAdd = false
                        }
                    }) {
                        Text("Add")
                    }
                }
                .padding()
            }
            .sheet(isPresented: $showEdit) {
                VStack {
                    Text("Edit Key")
                        .font(.title)
                    TextField("Key", text: $keys[editIndex])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("Value", text: $values[editIndex])
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Picker("Type", selection: $types[editIndex]) {
                        Text("String").tag("String")
                        Text("Integer").tag("Integer")
                        Text("Boolean").tag("Boolean")
                        Text("Float").tag("Float")
                        Text("Double").tag("Double")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    Button(action: {
                        showEdit = false
                    }) {
                        Text("Done")
                    }
                }
                .padding()
            }
            .alert(isPresented: $showDelete) {
                Alert(title: Text("Delete Key"), message: Text("Are you sure you want to delete the key \(keys[deleteIndex])?"), primaryButton: .destructive(Text("Delete")) {
                    keys.remove(at: deleteIndex)
                    values.remove(at: deleteIndex)
                    types.remove(at: deleteIndex)
                    showDelete = false
                }, secondaryButton: .cancel())
            }
            HStack {
                Button(action: {
                    showAdd = true
                }) {
                    Text("Add")
                }
                Spacer()
                Button(action: {
                    // save the plist
                    for index in keys.indices {
                        if types[index] == "String" {
                            plist[keys[index]] = values[index]
                        } else if types[index] == "Integer" {
                            plist[keys[index]] = Int(values[index])
                        } else if types[index] == "Boolean" {
                            plist[keys[index]] = Bool(values[index])
                        } else if types[index] == "Float" {
                            plist[keys[index]] = Float(values[index])
                        } else if types[index] == "Double" {
                            plist[keys[index]] = Double(values[index])
                        }
                    }
                    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                    // use the CVE to write the file
                   // overwriteFile(fileDataLocked: data, pathtovictim: path)
                    if (overwriteFile(fileDataLocked: data, pathtovictim: path)) {
                        // alert the user that the file was saved
                        let alert = UIAlertController(title: "Success", message: "The file was saved successfully.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                    } else {
                        // alert the user that the file was not saved
                        let alert = UIAlertController(title: "Error", message: "The file was not saved successfully.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                    }
                }) {
                    Text("Save")
                }
            }
        }
        .onAppear {
            let data = try! Data(contentsOf: URL(fileURLWithPath: path))
            plist = try! PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
            for (key, value) in plist {
                keys.append(key)
                if value is String {
                    values.append(value as! String)
                    types.append("String")
                } else if value is Int {
                    values.append(String(value as! Int))
                    types.append("Integer")
                } else if value is Bool {
                    values.append(String(value as! Bool))
                    types.append("Boolean")
                } else if value is Float {
                    values.append(String(value as! Float))
                    types.append("Float")
                } else if value is Double {
                    values.append(String(value as! Double))
                    types.append("Double")
                }
            }
        }
    }
}

// TextEditorView, a view that allows the user to edit a file if it isn't a plist
struct TextEditorView: View {
    @State var path: String
    @State var text: String = ""
    var body: some View {
        VStack {
            TextEditor(text: $text)
                .padding()
            HStack {
                Spacer()
                Button(action: {
                    // save the file
                    let data = text.data(using: .utf8)!
                    // use the CVE to write the file
                    //overwriteFile(fileDataLocked: data, pathtovictim: path)
                    if (overwriteFile(fileDataLocked: data, pathtovictim: path)) {
                        // alert the user that the file was saved
                        let alert = UIAlertController(title: "Success", message: "The file was saved successfully.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                    } else {
                        // alert the user that the file was not saved
                        let alert = UIAlertController(title: "Error", message: "The file was not saved successfully.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                    }
                }) {
                    Text("Save")
                }
            }
        }
        .onAppear {
            do {
                text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            } catch {
                let alert = UIAlertController(title: "Error", message: "The file could not be opened.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                UIApplication.shared.windows.first?.rootViewController?.dismiss(animated: true, completion: {
                    UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true, completion: nil)
                })
            }
        }
    }
}

struct ContentView: View {
    @State var path: String = "/"
    var body: some View {
        NavigationView {
            FileManagerView(path: path)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
