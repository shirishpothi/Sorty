//
//  LabFileParticle.swift
//  Sorty
//
//  Lightweight file particle for the Sorting Lab
//

import SwiftUI
import UniformTypeIdentifiers

struct LabFileParticle: View {
    let fileName: String
    let isActive: Bool

    private var fileExtension: String {
        let ext = (fileName as NSString).pathExtension
        return ext.isEmpty ? "" : ext
    }

    private var fileIcon: NSImage {
        AnalysisIconProvider.icon(forFileExtension: fileExtension)
    }

    var body: some View {
        ZStack {
            if isActive {
                trailEffect
            }

            Image(nsImage: fileIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .shadow(
                    color: isActive ? .cyan.opacity(0.8) : .clear,
                    radius: isActive ? 6 : 0
                )
                .shadow(
                    color: isActive ? .cyan.opacity(0.4) : .clear,
                    radius: isActive ? 10 : 0
                )
        }
        .frame(width: 30, height: 30)
        .help(fileName)
        .accessibilityIdentifier("LabFileParticle")
    }

    private var trailEffect: some View {
        HStack(spacing: -4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.cyan.opacity(0.3 - Double(index) * 0.1))
                    .frame(width: 6 - CGFloat(index), height: 6 - CGFloat(index))
                    .blur(radius: 1 + CGFloat(index))
            }
        }
        .offset(x: -12)
    }
}

#Preview {
    HStack(spacing: 20) {
        LabFileParticle(fileName: "report.pdf", isActive: false)
        LabFileParticle(fileName: "photo.jpg", isActive: true)
        LabFileParticle(fileName: "notes.txt", isActive: true)
        LabFileParticle(fileName: "archive.zip", isActive: false)
    }
    .padding(40)
    .background(.black.opacity(0.8))
}
