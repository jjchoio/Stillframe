//
//  ImageWriter.swift
//  Stillframe
//

import CoreGraphics
import Foundation
import ImageIO

enum ImageWriterError: LocalizedError {
    case cannotCreateDestination(URL)
    case encodingFailed(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreateDestination(let url):
            "Couldn't create an image file at \(url.lastPathComponent)."
        case .encodingFailed(let url):
            "Couldn't write \(url.lastPathComponent)."
        }
    }
}

enum ImageWriter {
    /// Encodes `image` to `url`. The extension of `url` must match `format`.
    static func write(_ image: CGImage, to url: URL, format: ImageFormat, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil)
        else {
            throw ImageWriterError.cannotCreateDestination(url)
        }

        // Quality is meaningless for PNG, and passing it does no harm — but keeping it off the
        // dictionary makes the lossless path unambiguous.
        let properties: CFDictionary? = format.isLossy
            ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            : nil

        CGImageDestinationAddImage(destination, image, properties)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageWriterError.encodingFailed(url)
        }
    }
}
