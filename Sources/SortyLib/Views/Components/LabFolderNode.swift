//
//  LabFolderNode.swift
//  Sorty
//
//  Floating folder destination node for the Sorting Lab visualization.
//

import SwiftUI
import UniformTypeIdentifiers

struct LabFolderNode: View {
    let folderName: String
    let fileCount: Int
    let isLoading: Bool
    let isReceivingFile: Bool
    var accentColor: Color = .cyan

    @State private var appeared = false
    @State private var bobOffset: CGFloat = 0
    @State private var loadingOpacity: Double = 1.0
    @State private var receivingGlow = false

    private static let systemFolderIcon: NSImage = {
        NSWorkspace.shared.icon(for: .folder).copy() as! NSImage
    }()

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: Self.systemFolderIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)

            Text(folderName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(width: 100, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    accentColor.opacity(receivingGlow ? 0.8 : 0),
                    lineWidth: 2
                )
        )
        .opacity(isLoading ? loadingOpacity : 1.0)
        .offset(y: bobOffset)
        .scaleEffect(appeared ? 1.0 : 0.3)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appeared = true
            }
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                bobOffset = -3
            }
        }
        .onChange(of: isLoading) { _, loading in
            if loading {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    loadingOpacity = 0.5
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    loadingOpacity = 1.0
                }
            }
        }
        .onChange(of: isReceivingFile) { _, receiving in
            if receiving {
                withAnimation(.easeIn(duration: 0.15)) {
                    receivingGlow = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) {
                    receivingGlow = false
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folderName) folder, \(fileCount) files")
        .accessibilityIdentifier("LabFolderNode")
    }
}

#Preview("Lab Folder Node") {
    HStack(spacing: 24) {
        LabFolderNode(
            folderName: "Documents",
            fileCount: 3,
            isLoading: false,
            isReceivingFile: false
        )
        LabFolderNode(
            folderName: "Loading Folder",
            fileCount: 0,
            isLoading: true,
            isReceivingFile: false,
            accentColor: .purple
        )
        LabFolderNode(
            folderName: "Receiving",
            fileCount: 5,
            isLoading: false,
            isReceivingFile: true,
            accentColor: .green
        )
    }
    .padding(40)
    .background(.black.opacity(0.8))
}
