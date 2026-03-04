//
//  ValidationReviewView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import SwiftUI
import UIKit

// MARK: - Root view

struct ValidationReviewView: View {
    let result: ReceiptValidationResult
    let parsed: ParsedReceipt
    let images: [UIImage]
    var onSaveAnyway: () -> Void
    var onRescan: () -> Void

    @State private var currentIndex = 0
    @State private var cropCache: [Int: UIImage] = [:]

    private var sorted: [ReceiptValidationIssue] { result.sortedIssues }
    private var total: Int { sorted.count }

    var body: some View {
        VStack(spacing: 0) {
            ProgressBar(current: currentIndex, total: total)
                .padding(.horizontal)
                .padding(.top, 8)

            if currentIndex < total {
                Text("Issue \(currentIndex + 1) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                IssueCardView(
                    issue: sorted[currentIndex],
                    cropImage: cropCache[currentIndex]
                ) {
                    withAnimation { currentIndex += 1 }
                }
                .padding()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(currentIndex)
            } else {
                FinalCardView(
                    result: result,
                    onSaveAnyway: onSaveAnyway,
                    onRescan: onRescan
                )
                .padding()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }

            Spacer()
        }
        .navigationTitle("Review Issues")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    // Pop back to ReceiptReviewView without saving
                    // NavigationStack will handle the pop when showingValidation is set false.
                    // We accomplish this by hijacking back navigation only on the final screen;
                    // for issue cards we show a custom back button instead.
                }
                .hidden() // Replaced by custom back button on issue cards
            }
        }
        .task {
            for (i, issue) in result.sortedIssues.enumerated() {
                guard cropCache[i] == nil else { continue }
                if let box = issue.associatedBoundingBox, let image = images.first {
                    cropCache[i] = crop(box, from: image, xPad: 0.02, yPad: 0.012)
                }
            }
        }
    }

    // MARK: - Crop helper

    private func crop(_ box: CGRect, from image: UIImage, xPad: CGFloat, yPad: CGFloat) -> UIImage? {
        // Vision uses bottom-left origin; CGImage uses top-left origin.
        guard let cgImage = image.cgImage else { return nil }
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let padded = box
            .insetBy(dx: -xPad, dy: -yPad)            // negative inset = expand
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let rect = CGRect(
            x:      padded.minX * w,
            y:      (1 - padded.maxY) * h,            // flip Y: Vision bottom-left → CGImage top-left
            width:  padded.width * w,
            height: padded.height * h
        )
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Progress bar

private struct ProgressBar: View {
    let current: Int
    let total: Int

    var progress: Double {
        total == 0 ? 1.0 : Double(current) / Double(total)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemFill))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.25), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Issue card

private struct IssueCardView: View {
    let issue: ReceiptValidationIssue
    let cropImage: UIImage?
    var onNext: () -> Void

    private var iconColor: Color {
        switch issue.severity {
        case .info:     return .blue
        case .warning:  return .orange
        case .error:    return .red
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: issue.iconName)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .padding(.top, 8)

            if let crop = cropImage {
                Image(uiImage: crop)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 60)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(spacing: 8) {
                Text(issue.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(issue.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Next", action: onNext)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Final card

private struct FinalCardView: View {
    let result: ReceiptValidationResult
    var onSaveAnyway: () -> Void
    var onRescan: () -> Void

    private var summaryIcon: String {
        result.preferRescan ? "arrow.counterclockwise.camera" : "checkmark.circle"
    }

    private var summaryColor: Color {
        result.preferRescan ? .orange : .green
    }

    private var summaryMessage: String {
        if result.preferRescan {
            return "There are significant quality issues with this receipt. We recommend rescanning for better results."
        } else {
            return "You've reviewed all issues. You can save the receipt as-is or rescan for a cleaner result."
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: summaryIcon)
                .font(.system(size: 48))
                .foregroundStyle(summaryColor)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Review Complete")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(summaryMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                if result.preferRescan {
                    Button("Rescan Receipt", action: onRescan)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Save Anyway", action: onSaveAnyway)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Save Anyway", action: onSaveAnyway)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)

                    Button("Rescan Receipt", action: onRescan)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
