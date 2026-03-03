//
//  ValidationReviewView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/3/26.
//

import SwiftUI

// MARK: - Root view

struct ValidationReviewView: View {
    let result: ReceiptValidationResult
    var onSaveAnyway: () -> Void
    var onRescan: () -> Void

    @State private var currentIndex = 0

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

                IssueCardView(issue: sorted[currentIndex]) {
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
