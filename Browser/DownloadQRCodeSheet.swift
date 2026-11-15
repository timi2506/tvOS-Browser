//
//  DownloadQRCodeSheet.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI
import CoreImage
import UIKit

struct DownloadQRCodeSheet: View {
    let download: PendingDownload
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var qrImage: UIImage?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(download.filename)
                        .font(.title3)
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Text("Scan with your phone's camera to download this file")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                
                if let qrImage = qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 320, height: 320)
                        .padding(18)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                } else {
                    ProgressView()
                        .frame(width: 320, height: 320)
                }
                
                Text(download.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 700)
                
                HStack(spacing: 24) {
                    Button {
                        downloadManager.startDownload(from: download.url, suggestedFilename: download.filename)
                        dismiss()
                    } label: {
                        Label("Download on Apple TV", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(40)
            .navigationTitle("Download File")
            .onAppear {
                qrImage = generateQRCode(from: download.url.absoluteString)
            }
            #if os(tvOS)
            .onExitCommand {
                dismiss()
            }
            #endif
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
