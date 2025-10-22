# 📦 Shipment Insurance Smart Contract

A decentralized shipment insurance solution built on Stacks blockchain using Clarity smart contracts. Automate insurance claims for damaged or delayed shipments with oracle integration and escrow functionality.

## 🚀 Features

- **Automated Claims Processing** - Oracle-triggered payouts for late or damaged shipments
- **Escrow Protection** - Premiums locked in smart contract until resolution
- **Flexible Policies** - Customizable coverage based on shipment value, route, and duration
- **Multi-party Support** - Separate roles for shippers, receivers, and oracles
- **Real-time Tracking** - Integration with delivery status updates

## 📋 Contract Overview

### Core Functions

#### 🔧 Admin Functions
- `set-oracle` - Set authorized oracle for delivery updates
- `process-claim` - Manual claim processing by contract owner

#### 📝 Policy Management
- `create-policy` - Create new insurance policy with premium escrow
- `cancel-policy` - Cancel active policy and refund premium
- `expire-policy` - Mark expired policies and transfer premiums

#### 🎯 Claims Process
- `submit-claim` - Submit insurance claim with evidence
- `oracle-update-delivery` - Automated oracle updates for delivery status

#### 📊 Read-Only Functions
- `get-policy` - Retrieve policy details
- `get-claim` - Get claim information
- `get-contract-stats` - View contract statistics
- `calculate-premium` - Calculate premium for given parameters

## 🛠 Usage Guide

### Creating a Policy

```clarity
(contract-call? .shipment-insurance create-policy
  'SP2RECEIVER...  ;; receiver address
  u1000000         ;; shipment value (1 STX)
  u50000           ;; premium amount (0.05 STX)
  u144             ;; coverage duration (144 blocks ≈ 24 hours)
  "NYC-LA"         ;; route
  "TRK123456"      ;; tracking ID
)
```

### Submitting a Claim

```clarity
(contract-call? .shipment-insurance submit-claim
  u1               ;; policy ID
  u1               ;; claim type (1=damaged, 2=delayed)
  u500000          ;; claim amount (0.5 STX)
  "Package damaged in transit"  ;; evidence
)
```

### Oracle Integration

```clarity
(contract-call? .shipment-insurance oracle-update-delivery
  u1     ;; policy ID
  true   ;; delivered
  false  ;; on-time (false = delayed)
)
```

## 🔍 Policy Status Codes

- `1` - Active
- `2` - Claimed
- `3` - Expired
- `4` - Cancelled

## 🎯 Claim Types

- `1` - Damaged shipment (full coverage)
- `2` - Delayed shipment (50% coverage)

## 🔒 Security Features

- **Owner-only functions** for critical operations
- **Policy validation** prevents invalid claims
- **Time-based expiration** for automatic policy resolution
- **Oracle authorization** system for trusted delivery updates

## 💰 Premium Calculation

Base premium calculation:
```
Premium = (Shipment Value × Base Rate × Risk Multiplier) / 10000
```

- Base Rate: 5% (0.05)
- Risk Multiplier: 100 + (Route Risk × 10)

## 🧪 Testing

Run contract tests:
```bash
npm install
npm test
```

Check contract syntax:
```bash
clarinet check
```

## 📈 Contract Statistics

View real-time contract metrics:
- Total policies created
- Total claims processed  
- Total funds locked in escrow
- Current oracle address

## 🌐 Deployment

1. Deploy to testnet:
```bash
clarinet publish --testnet
```

2. Deploy to mainnet:
```bash
clarinet publish --mainnet
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Ensure `clarinet check` passes
5. Submit pull request

## 📄 License

MIT License - see LICENSE file for details

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Developer Tools](https://github.com/hirosystems/clarinet)

---

Built with ❤️ on Stacks blockchain for decentralized logistics insurance
