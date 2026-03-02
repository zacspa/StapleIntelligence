//
//  ReceiptsView.swift
//  StapleIntelligence
//
//  Created by Zack Sparks on 3/2/26.
//

import SwiftUI
import SwiftData

struct ReceiptsView: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    ContentUnavailableView(
                        "No Receipts",
                        systemImage: "receipt",
                        description: Text("Tap + to scan your first receipt.")
                    )
                } else {
                    List(receipts) { receipt in
                        Text(receipt.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")
                    }
                }
            }
            .navigationTitle("Receipts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // TODO: trigger scan
                    } label: {
                        Label("Add Receipt", systemImage: "plus")
                    }
                }
            }
        }
    }
}

#Preview {
    ReceiptsView()
        .modelContainer(for: [Receipt.self, LineItem.self, Merchant.self], inMemory: true)
}
