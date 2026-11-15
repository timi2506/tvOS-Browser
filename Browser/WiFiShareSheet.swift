//
//  WiFiShareSheet.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI
import CoreImage
import UIKit

struct WiFiShareSheet: View {
    let item: DownloadItem?
    @ObservedObject var fileServer = FileServerManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    
    var shareURL: URL? {
        if let item = item {
            return fileServer.urlForFile(item)
        }
        return fileServer.serverURL
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let item = item {
                    VStack(spacing: 6) {
                        Text(item.filename)
                            .font(.title3)
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text("\(item.formattedSize) • \(item.formattedDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("Wi-Fi Downloads Server")
                            .font(.title3)
                            .bold()
                        
                        Text("Transfer files from Apple TV to your devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 16) {
                    Label(fileServer.isRunning ? "Server Running" : "Server Stopped", systemImage: fileServer.isRunning ? "network" : "network.slash")
                        .font(.headline)
                        .foregroundStyle(fileServer.isRunning ? .green : .secondary)
                    
                    Spacer()
                    
                    Button(fileServer.isRunning ? "Stop Server" : "Enable Server") {
                        fileServer.toggle()
                        updateQRCode()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(fileServer.isRunning ? .red : .blue)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                .frame(maxWidth: 680)
                
                if fileServer.isRunning, let targetURL = shareURL {
                    VStack(spacing: 16) {
                        if let qrImage = qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 260, height: 260)
                                .padding(16)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
                        } else {
                            ProgressView()
                                .frame(width: 260, height: 260)
                        }
                        
                        Text(targetURL.absoluteString)
                            .font(.system(.callout, design: .monospaced))
                            .bold()
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 680)
                        
                        Text("Scan with your phone's camera, or open this URL in any browser on your Mac or PC.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 600)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.router")
                            .font(.system(size: 70))
                            .foregroundStyle(.secondary)
                        
                        Text("Enable the server above to download this file on your Mac, phone, or PC connected to the same Wi-Fi network.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 550)
                    }
                    .frame(height: 280)
                }
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(32)
            .navigationTitle("Wi-Fi File Transfer")
            .onAppear {
                if !fileServer.isRunning {
                    fileServer.start()
                }
                updateQRCode()
            }
            .onChange(of: fileServer.isRunning) { _ in
                updateQRCode()
            }
#if os(tvOS)
            .onExitCommand {
                dismiss()
            }
            #endif
        }
    }
    
    private func updateQRCode() {
        if let url = shareURL {
            qrImage = generateQRCode(from: url.absoluteString)
        } else {
            qrImage = nil
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
