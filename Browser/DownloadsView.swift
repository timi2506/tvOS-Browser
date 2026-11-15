//
//  DownloadsView.swift
//  Browser
//
//  Created for tvOS Web Browser.
//

import SwiftUI
import Combine

struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var fileServer = FileServerManager.shared
    @State private var showingClearConfirmation = false
    @State private var selectedFileForPreview: DownloadItem?
    @State private var qrDownload: PendingDownload?
    @State private var sharingFileItem: DownloadItem?
    @State private var showingServerSheet = false
    
    init() {}
    
    var body: some View {
        VStack(spacing: 20) {
            if downloadManager.downloads.isEmpty && downloadManager.activeDownloads.isEmpty {
                VStack(spacing: 25) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 80))
                        .foregroundStyle(.secondary)
                    Text("No Downloads Yet")
                        .font(.title2)
                        .bold()
                    Text("Files downloaded from websites will appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !downloadManager.activeDownloads.isEmpty {
                        Section(header: Text("Downloading")) {
                            ForEach(Array(downloadManager.activeDownloads.keys), id: \.self) { id in
                                HStack(spacing: 15) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Downloading file...")
                                            .font(.headline)
                                        ProgressView(value: downloadManager.activeDownloads[id] ?? 0.0)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    
                    Section(header: HStack {
                        Text("Downloaded Files (\(downloadManager.downloads.count))")
                        Spacer()
                        if !downloadManager.downloads.isEmpty {
                            Button(action: {
                                showingServerSheet = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: fileServer.isRunning ? "wifi" : "wifi.slash")
                                    Text("Wi-Fi Share")
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(fileServer.isRunning ? .green : .blue)
                            
                            Button("Clear All", role: .destructive) {
                                showingClearConfirmation = true
                            }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                    }) {
                        ForEach(downloadManager.downloads) { item in
                            HStack(spacing: 20) {
                                Image(systemName: item.iconName)
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tint)
                                    .frame(width: 50, height: 50)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.filename)
                                        .font(.headline)
                                        .lineLimit(1)
                                    HStack(spacing: 12) {
                                        Text(item.formattedSize)
                                        Text("•")
                                        Text(item.formattedDate)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if let originalURL = item.originalURL {
                                    Button(action: {
                                        qrDownload = PendingDownload(url: originalURL, filename: item.filename)
                                    }) {
                                        Image(systemName: "qrcode")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                Button(action: {
                                    sharingFileItem = item
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)
                                
                                Button(role: .destructive, action: {
                                    withAnimation {
                                        downloadManager.deleteDownload(item)
                                    }
                                }) {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .padding(.vertical, 4)
                            .contextMenu {
                                if let originalURL = item.originalURL {
                                    Button(action: {
                                        qrDownload = PendingDownload(url: originalURL, filename: item.filename)
                                    }) {
                                        Label("Show QR Code", systemImage: "qrcode")
                                    }
                                }
                                
                                Button(action: {
                                    sharingFileItem = item
                                }) {
                                    Label("Share via Wi-Fi", systemImage: "square.and.arrow.up")
                                }
                                
                                Button(role: .destructive, action: {
                                    withAnimation {
                                        downloadManager.deleteDownload(item)
                                    }
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .sheet(item: $qrDownload) { item in
            DownloadQRCodeSheet(download: item)
                .frame(minWidth: 1000, minHeight: 800)
        }
        .sheet(item: $sharingFileItem) { item in
            WiFiShareSheet(item: item)
                .frame(minWidth: 1000, minHeight: 800)
        }
        .sheet(isPresented: $showingServerSheet) {
            WiFiShareSheet(item: nil)
                .frame(minWidth: 1000, minHeight: 800)
        }
        .confirmationDialog("Clear all downloads?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Delete All Files", role: .destructive) {
                withAnimation {
                    downloadManager.clearAllDownloads()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all downloaded files from your device.")
        }
    }
}
