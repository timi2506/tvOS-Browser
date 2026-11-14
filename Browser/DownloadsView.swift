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
    @State private var showingClearConfirmation = false
    @State private var selectedFileForPreview: DownloadItem?
    
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
                        }
                    }
                }
            }
        }
        .navigationTitle("Downloads")
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
