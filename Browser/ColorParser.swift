//
//  ColorParser.swift
//  Browser
//
//  Created by Tim on 14.11.26.
//

import SwiftUI
import SwiftSoup
import FaviconFinder
import CoreImage

#if canImport(UIKit)
import UIKit
public typealias NativeColor = UIColor
public typealias NativeImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias NativeColor = NSColor
public typealias NativeImage = NSImage
#endif

public enum WebsiteColorError: Error {
    case invalidURL
    case colorNotFound
}

public struct WebsiteColorParser {
    
    public static func getColor(for urlString: String) async throws -> NativeColor {
        guard let url = URL(string: urlString) else {
            throw WebsiteColorError.invalidURL
        }
        
        let themeColor = try? await fetchThemeColor(from: url)
        
        if let color = themeColor, !color.isTooWhiteBlackOrGray {
            return color
        }
        
        let faviconColor = try? await fetchFaviconColor(from: url)
        
        if let color = faviconColor, !color.isTooWhiteBlackOrGray {
            return color
        }
        
        if let color = faviconColor {
            return color
        }
        
        if let color = themeColor {
            return color
        }
        
        throw WebsiteColorError.colorNotFound
    }
    
    private static func fetchThemeColor(from url: URL) async throws -> NativeColor? {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let doc = try SwiftSoup.parse(html)
        if let themeColorElement = try doc.select("meta[name=theme-color]").first() {
            let hexString = try themeColorElement.attr("content")
            return NativeColor(hex: hexString)
        }
        
        return nil
    }
    
    private static func fetchFaviconColor(from url: URL) async throws -> NativeColor? {
        let faviconFinderURLs = try await FaviconFinder(url: url).fetchFaviconURLs()

        let urls = faviconFinderURLs.sorted { one, two in
            func priority(for format: FaviconFormatType) -> Int {
                switch format {
                case .icon: return 0
                case .appleTouchIcon: return 1
                default: return 2
                }
            }
            
            return priority(for: one.format) < priority(for: two.format)
        }
        guard let favicon = try await urls.first?.download() else { throw URLError(.dataNotAllowed) }
        return favicon.image?.image.dominantColor
    }
}

public extension NativeColor {
    var isTooWhiteBlackOrGray: Bool {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        #if canImport(UIKit)
        guard getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return false }
        #elseif canImport(AppKit)
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else { return false }
        rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #endif
        
        if b < 0.25 { return true }
        if s < 0.15 { return true }
        
        return false
    }
    
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r, g, b, a: CGFloat
        let length = hexSanitized.count
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

public extension NativeImage {
    var dominantColor: NativeColor? {
        #if canImport(UIKit)
        guard let cgImage = self.cgImage else { return nil }
        let inputImage = CIImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapImage.cgImage else { return nil }
        let inputImage = CIImage(cgImage: cgImage)
        #endif
        
        let extentVector = CIVector(x: inputImage.extent.origin.x,
                                    y: inputImage.extent.origin.y,
                                    z: inputImage.extent.size.width,
                                    w: inputImage.extent.size.height)
        
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]),
              let outputImage = filter.outputImage else { return nil }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(outputImage,
                       toBitmap: &bitmap,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: nil)
        
        return NativeColor(red: CGFloat(bitmap[0]) / 255,
                           green: CGFloat(bitmap[1]) / 255,
                           blue: CGFloat(bitmap[2]) / 255,
                           alpha: CGFloat(bitmap[3]) / 255)
    }
}

extension Color: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let r = try container.decode(Double.self, forKey: .red)
        let g = try container.decode(Double.self, forKey: .green)
        let b = try container.decode(Double.self, forKey: .blue)
        let a = try container.decode(Double.self, forKey: .alpha)
        
        self.init(red: r, green: g, blue: b, opacity: a)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        #if canImport(UIKit)
        if UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) {
            try container.encode(Double(r), forKey: .red)
            try container.encode(Double(g), forKey: .green)
            try container.encode(Double(b), forKey: .blue)
            try container.encode(Double(a), forKey: .alpha)
        }
        #elseif canImport(AppKit)
        if let rgbColor = NSColor(self).usingColorSpace(.deviceRGB) {
            rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            try container.encode(Double(r), forKey: .red)
            try container.encode(Double(g), forKey: .green)
            try container.encode(Double(b), forKey: .blue)
            try container.encode(Double(a), forKey: .alpha)
        }
        #endif
    }
}
