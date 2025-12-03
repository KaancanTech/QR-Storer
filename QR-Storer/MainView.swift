//
//  MainView.swift
//  QR-Storer
//
//  Created by Mixon on 25.11.2025.
//

import SwiftUI

// Ключ для UserDefaults
let tabsKey = "qrTabs"

import SwiftUI
import Vision
import UIKit

extension String: Identifiable {
    public var id: String { self }
}

struct PreviewItem: Identifiable{
    let id = UUID()
    let image: UIImage
    let text: String
    let title: String
}

struct MainView: View {
    @State private var tabs: [String] = {
        var saved = UserDefaults.standard.stringArray(forKey: tabsKey) ?? ["All", "Shop", "Gas", "Service", "Contacts"]
        if !saved.contains("All") {
            saved.insert("All", at: 0)
        } else if saved.first != "All" {
            saved.removeAll { $0 == "All" }
            saved.insert("All", at: 0)
        }
        return saved
    }()
    
    @State private var selectedTab: String = "All"
    @State private var showingManageTabs = false
    @State private var showingAddQR = false
    
    @State private var savedQRs: [[String: String]] = UserDefaults.standard.array(forKey: "savedQRs") as? [[String: String]] ?? []
    
    // preview state
//    @State private var previewImage: UIImage?
    @State private var decodedItem: PreviewItem?
    
    var filteredQRs: [[String: String]] {
        if selectedTab == "All" { return savedQRs }
        return savedQRs.filter { $0["category"] == selectedTab }
    }

    
    var body: some View {
        VStack {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .padding(.top, 20)
            
            // Горизонтальный скролл
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(tabs, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(selectedTab == tab ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(selectedTab == tab ? .white : .black)
                                .cornerRadius(20)
                        }
                    }
                    
                    Button {
                        showingManageTabs = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .sheet(isPresented: $showingManageTabs, onDismiss: loadTabs) {
                ManageTabsView()
            }
            
            Divider().padding(.vertical, 10)

            // ⬇️ СЕТКА QR-кодов
            if filteredQRs.isEmpty {
                Text("No saved QR-codes")
                    .foregroundColor(.gray)
                    .padding(.top, 40)
            } else {
                ScrollView {
                    let columns = [ GridItem(.flexible()), GridItem(.flexible()) ]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredQRs, id: \.self) { item in
                            // ожидаем, что в item есть ключ "fileName" (как сохраняет AddQRCodeView)
                            if let fileName = item["fileName"],
                               let image = loadImageFromDocuments(fileName: fileName) {
                                
                                Button {
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        let result = scanQRCode(from: image)
                                        DispatchQueue.main.async {
                                            decodedItem = PreviewItem(image: image, text: result ?? "No QR", title: item["title"] ?? "Saved QR")

                                        }
                                    }
                                } label: {
                                    VStack {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: UIScreen.main.bounds.width*0.43, height: UIScreen.main.bounds.height*0.2)
                                            .clipped()
                                            .cornerRadius(12)
                                            .shadow(radius: 3)
                                        
                                        let title = item["title"] ?? "QR"
                                        Text("\(title)")
                                            .foregroundStyle(.black).bold()
                                        
                                    }
                                }
                                
                            } else {
                                // плейсхолдер + лог в консоль, чтобы было проще дебажить
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 140)
                                    .cornerRadius(12)
                                    .overlay(
                                        Text("No Image")
                                            .foregroundColor(.gray)
                                    )
                                    .onTapGesture {
                                        print("⚠️ image load failed for item:", item)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

            }

            Spacer()

            Button(action: {
                showingAddQR = true
            }) {
                Text("Add QR code")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .sheet(isPresented: $showingAddQR, onDismiss: loadSavedQRs) {
                AddQRCodeView()
            }
        }

        .sheet(item: $decodedItem, content: { item in
            QRPreviewView(image: item.image, decodedText: item.text, title: item.title)
        })
        .onAppear {
            loadSavedQRs()
            if !UserDefaults.standard.bool(forKey: "firstLaunch") {
                UserDefaults.standard.set(["All", "Shop", "Gas", "Service", "Contacts"], forKey: tabsKey)
                UserDefaults.standard.set(true, forKey: "firstLaunch")
            }
        }
    }
    
    // MARK: - Helpers
    // Загружает UIImage из Documents по имени файла
    func loadImageFromDocuments(fileName: String) -> UIImage? {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }

    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    
    func loadSavedQRs() {
        savedQRs = UserDefaults.standard.array(forKey: "savedQRs") as? [[String: String]] ?? []
    }
    
    func loadTabs() {
        tabs = UserDefaults.standard.stringArray(forKey: tabsKey) ?? ["All"]
        if !tabs.contains(selectedTab) {
            selectedTab = tabs.first ?? "All"
        }
    }
    
    func decode(base64: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}



func prepareImageForScan(_ image: UIImage, maxDimension: CGFloat = 1000) -> CGImage? {
    // Сжимаем до безопасного размера
    let size = image.size
    let scale = max(size.width, size.height) / maxDimension
    let newSize = scale > 1 ? CGSize(width: size.width/scale, height: size.height/scale) : size

    // Рисуем в контекст без альфа, RGB
    UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
    let context = UIGraphicsGetCurrentContext()
    context?.setFillColor(UIColor.white.cgColor)
    context?.fill(CGRect(origin: .zero, size: newSize))
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let processedImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return processedImage?.cgImage
}

func scanQRCode(from image: UIImage) -> String? {
    guard let cgImage = prepareImageForScan(image) else { return nil }

    let request = VNDetectBarcodesRequest { request, error in
      guard let results = request.results as? [VNBarcodeObservation] else { return }
      // читаем payloadStringValue
    }
    request.symbologies = [.qr]
    request.revision = VNDetectBarcodesRequestRevision1

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    var result: String?

    do {
        try handler.perform([request])
        if let observation = request.results?.first as? VNBarcodeObservation,
           let payload = observation.payloadStringValue {
            result = payload
        }
    } catch {
        print("❌ Vision error:", error)
    }

    return result
}


func resizeImage(_ image: UIImage, maxDimension: CGFloat = 1000) -> UIImage? {
    let size = image.size
    let scale = max(size.width, size.height) / maxDimension
    guard scale > 1 else { return image } // не масштабируем, если уже меньше
    let newSize = CGSize(width: size.width / scale, height: size.height / scale)
    
    UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: newSize))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return resized
}



// Экран управления вкладками
struct ManageTabsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var tabs: [String] = UserDefaults.standard.stringArray(forKey: tabsKey) ?? ["All"]
    @State private var newTab: String = ""
    
    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("New tab (max 12 chars)", text: $newTab)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: newTab) { newValue in
                            if newValue.count > 12 {
                                newTab = String(newValue.prefix(12))
                            }
                        }
                    
                    Button(action: {
                        addTab()
                    }) {
                        Text("Add")
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                
                List {
                    ForEach(tabs, id: \.self) { tab in
                        HStack {
                            Text(tab)
                            Spacer()
                            if tab != "All" { // нельзя удалить "All"
                                Button(action: {
                                    removeTab(tab)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Tabs")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func addTab() {
        let trimmed = newTab.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tabs.contains(trimmed) else { return }
        tabs.append(trimmed)
        UserDefaults.standard.set(tabs, forKey: tabsKey)
        newTab = ""
    }
    
    private func removeTab(_ tab: String) {
        tabs.removeAll { $0 == tab }
        UserDefaults.standard.set(tabs, forKey: tabsKey)
    }
}

import SwiftUI
import PhotosUI

struct AddQRCodeView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var usingCamera = false
    @State private var selectedCategory: String = "All"
    @State private var qrTitle: String = ""          // ⬅️ имя QR-кода
    
    // Загружаем категории из UserDefaults
    @State private var categories: [String] = UserDefaults.standard.stringArray(forKey: tabsKey) ?? ["All"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                
                // Превью выбранной картинки
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 250)
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 250)
                        .cornerRadius(12)
                        .overlay(Text("No Image Selected").foregroundColor(.gray))
                        .padding(.horizontal)
                }
                
                // Кнопки выбора источника
                HStack(spacing: 20) {
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Text("Choose from Gallery")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        usingCamera = true
                    }) {
                        Text("Take Photo")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                }
                
                // Категории
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: Color.gray.opacity(0.4), radius: 4, x: 0, y: 2)
                )
                .padding(.horizontal)
                
                // ⬇️ Поле для имени QR-кода
                TextField("Enter QR name (optional)", text: $qrTitle)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: Color.gray.opacity(0.4), radius: 4, x: 0, y: 2)
                    )
                    .padding(.horizontal)
                    .onChange(of: qrTitle) { _ in
                        if qrTitle.count > 20 {
                            qrTitle = String(qrTitle.prefix(20))
                        }
                    }

                
                Spacer()
                
                // Кнопка сохранить
                Button(action: saveQRCode) {
                    Text("Save QR Code")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedImage == nil ? Color.gray : Color.blue)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .disabled(selectedImage == nil)
                
            }
            .navigationTitle("Add QR Code")
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $selectedImage, useCamera: false)
            }
            .sheet(isPresented: $usingCamera) {
                ImagePicker(image: $selectedImage, useCamera: true)
            }
        }
        
    }
    
    func saveQRCode() {
        guard let image = selectedImage else { return }
        
        if let data = image.jpegData(compressionQuality: 0.9) {
            let filename = UUID().uuidString + ".jpg"
            let url = getDocumentsDirectory().appendingPathComponent(filename)
            try? data.write(to: url)
            
            // ⬇️ Добавили title
            var savedQRs = UserDefaults.standard.array(forKey: "savedQRs") as? [[String: String]] ?? []
            savedQRs.append([
                "fileName": filename,
                "category": selectedCategory,
                "title": qrTitle
            ])
            UserDefaults.standard.set(savedQRs, forKey: "savedQRs")
            
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}


// UIImagePickerController для SwiftUI
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var useCamera: Bool
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        print("👉 useCamera =", useCamera)
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = useCamera ? .camera : .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            picker.dismiss(animated: true)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct QRGridItemView: View {
    let fileName: String
    
    var body: some View {
        if let image = loadImage() {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .cornerRadius(12)
                .shadow(radius: 4)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 140)
                .cornerRadius(12)
        }
    }
    
    func loadImage() -> UIImage? {
        let url = getDocumentsDirectory().appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }
    
    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}


struct SavedQR: Identifiable, Codable {
    let id: UUID
    let imageData: Data
    let category: String
}


import SwiftUI
import Vision
struct QRPreviewView: View {
    let image: UIImage?
    let decodedText: String
    let title: String
    
    var body: some View {
        VStack(spacing: 10) {
            Text("\(title)")
                .font(.title)
                .foregroundStyle(.black).bold()
            
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: UIScreen.main.bounds.height*0.6)
                    .cornerRadius(16)
                    .padding()
            }
            
            Text("Decoded:")
                .font(.headline)
            
            Link(decodedText, destination: URL(string: decodedText)!)
                .font(.system(size: 24, weight: .medium).italic())
                .foregroundColor(.blue)
                .padding()
                .disabled(decodedText == "No QR")
            
            Spacer()
        }
        .padding()
        .padding(.top, 40)
    }
}


#Preview {
    MainView()
}

