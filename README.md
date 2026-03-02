# StapleIntelligence

A privacy-first iOS app that scans grocery receipts using on-device OCR, extracts structured line items, and generates spending and price-trend insights.

All processing happens on-device. No receipt data, OCR text, or PII is ever transmitted remotely.

## Features

- **Receipt scanning** — VisionKit document scanner with on-device OCR via the Vision framework
- **Spending dashboard** — weekly and monthly spend breakdowns
- **Price tracking** — item price history and movers (rolling 4-week average comparison)
- **Merchant breakdown** — spending by store
- **Privacy-first** — all data stored locally with SwiftData; no cloud sync

## Requirements

- iOS 18+
- Xcode 16+

## Architecture

```
Scan → OCR (on-device) → Parse → Review → Persist
```

The codebase is organized into three layers within a single app target:

```
StapleIntelligence/
├── Models/Public/        # SwiftData entities: Receipt, LineItem, Merchant
├── Engine/
│   ├── Public/           # InsightsEngineProtocol + output value types
│   ├── Impl/             # InsightsEngine (queries local ModelContext)
│   └── Fake/             # FakeInsightsEngine for previews and tests
└── Views/Public/         # Dashboard, Receipts, Insights, Settings
```

**Key design decisions:**
- `Decimal` values stored as `String` in SwiftData (not natively queryable as `Decimal`)
- OCR runs on-device via `VNRecognizeTextRequest`; raw text is never persisted beyond the `Receipt.rawOcrText` field and never leaves the device
- `InsightsEngine` is a pure computation struct with no UI dependencies — easy to unit test

## Privacy

- All receipt data is stored locally using SwiftData
- Raw OCR text and receipt images never leave the device
- No analytics SDKs, no crash reporters that transmit PII

## License

MIT
