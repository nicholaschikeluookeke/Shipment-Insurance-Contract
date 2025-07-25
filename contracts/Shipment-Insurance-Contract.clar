(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-invalid-policy (err u102))
(define-constant err-claim-already-processed (err u103))
(define-constant err-insufficient-premium (err u104))
(define-constant err-policy-expired (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-policy-active (err u107))
(define-constant err-invalid-oracle (err u108))

(define-constant policy-status-active u1)
(define-constant policy-status-claimed u2)
(define-constant policy-status-expired u3)
(define-constant policy-status-cancelled u4)

(define-constant claim-status-pending u1)
(define-constant claim-status-approved u2)
(define-constant claim-status-rejected u3)

(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var total-locked-funds uint u0)
(define-data-var oracle-address (optional principal) none)

(define-map policies
  { policy-id: uint }
  {
    shipper: principal,
    receiver: principal,
    shipment-value: uint,
    premium-amount: uint,
    coverage-amount: uint,
    start-block: uint,
    end-block: uint,
    status: uint,
    route: (string-ascii 50),
    tracking-id: (string-ascii 30)
  }
)

(define-map claims
  { claim-id: uint }
  {
    policy-id: uint,
    claimant: principal,
    claim-type: uint,
    claim-amount: uint,
    status: uint,
    submitted-at: uint,
    processed-at: (optional uint),
    evidence: (string-ascii 100)
  }
)

(define-map policy-premiums
  { policy-id: uint }
  { locked-amount: uint }
)

(define-map authorized-oracles
  { oracle: principal }
  { active: bool }
)

(define-public (set-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set oracle-address (some oracle))
    (map-set authorized-oracles { oracle: oracle } { active: true })
    (ok true)
  )
)

(define-public (create-policy 
  (receiver principal)
  (shipment-value uint)
  (premium-amount uint)
  (coverage-duration uint)
  (route (string-ascii 50))
  (tracking-id (string-ascii 30))
)
  (let
    (
      (policy-id (+ (var-get policy-counter) u1))
      (coverage-amount (* shipment-value u110))
      (start-block stacks-block-height)
      (end-block (+ stacks-block-height coverage-duration))
    )
    (asserts! (>= (stx-get-balance tx-sender) premium-amount) err-insufficient-premium)
    (try! (stx-transfer? premium-amount tx-sender (as-contract tx-sender)))
    
    (map-set policies
      { policy-id: policy-id }
      {
        shipper: tx-sender,
        receiver: receiver,
        shipment-value: shipment-value,
        premium-amount: premium-amount,
        coverage-amount: (/ coverage-amount u100),
        start-block: start-block,
        end-block: end-block,
        status: policy-status-active,
        route: route,
        tracking-id: tracking-id
      }
    )
    
    (map-set policy-premiums
      { policy-id: policy-id }
      { locked-amount: premium-amount }
    )
    
    (var-set policy-counter policy-id)
    (var-set total-locked-funds (+ (var-get total-locked-funds) premium-amount))
    (ok policy-id)
  )
)

(define-public (submit-claim 
  (policy-id uint)
  (claim-type uint)
  (claim-amount uint)
  (evidence (string-ascii 100))
)
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (claim-id (+ (var-get claim-counter) u1))
    )
    (asserts! (or (is-eq tx-sender (get shipper policy)) 
                  (is-eq tx-sender (get receiver policy))) err-unauthorized)
    (asserts! (is-eq (get status policy) policy-status-active) err-invalid-policy)
    (asserts! (<= stacks-block-height (get end-block policy)) err-policy-expired)
    (asserts! (<= claim-amount (get coverage-amount policy)) err-invalid-policy)
    
    (map-set claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        claimant: tx-sender,
        claim-type: claim-type,
        claim-amount: claim-amount,
        status: claim-status-pending,
        submitted-at: stacks-block-height,
        processed-at: none,
        evidence: evidence
      }
    )
    
    (var-set claim-counter claim-id)
    (ok claim-id)
  )
)

(define-public (process-claim (claim-id uint) (approved bool))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) err-not-found))
      (policy-id (get policy-id claim))
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (premium-info (unwrap! (map-get? policy-premiums { policy-id: policy-id }) err-not-found))
    )
    (asserts! (or (is-eq tx-sender contract-owner)
                  (is-some (var-get oracle-address))) err-unauthorized)
    (asserts! (is-eq (get status claim) claim-status-pending) err-claim-already-processed)
    
    (if approved
      (begin
        (try! (as-contract (stx-transfer? (get claim-amount claim) tx-sender (get claimant claim))))
        (map-set policies
          { policy-id: policy-id }
          (merge policy { status: policy-status-claimed })
        )
        (map-set claims
          { claim-id: claim-id }
          (merge claim { 
            status: claim-status-approved,
            processed-at: (some stacks-block-height)
          })
        )
        (var-set total-locked-funds (- (var-get total-locked-funds) (get claim-amount claim)))
      )
      (map-set claims
        { claim-id: claim-id }
        (merge claim { 
          status: claim-status-rejected,
          processed-at: (some stacks-block-height)
        })
      )
    )
    (ok approved)
  )
)

(define-public (cancel-policy (policy-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (premium-info (unwrap! (map-get? policy-premiums { policy-id: policy-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get shipper policy)) err-unauthorized)
    (asserts! (is-eq (get status policy) policy-status-active) err-policy-active)
    
    (try! (as-contract (stx-transfer? (get locked-amount premium-info) tx-sender (get shipper policy))))
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { status: policy-status-cancelled })
    )
    
    (var-set total-locked-funds (- (var-get total-locked-funds) (get locked-amount premium-info)))
    (ok true)
  )
)

(define-public (expire-policy (policy-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (premium-info (unwrap! (map-get? policy-premiums { policy-id: policy-id }) err-not-found))
    )
    (asserts! (> stacks-block-height (get end-block policy)) err-invalid-policy)
    (asserts! (is-eq (get status policy) policy-status-active) err-policy-active)
    
    (try! (as-contract (stx-transfer? (get locked-amount premium-info) tx-sender contract-owner)))
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { status: policy-status-expired })
    )
    
    (var-set total-locked-funds (- (var-get total-locked-funds) (get locked-amount premium-info)))
    (ok true)
  )
)

(define-public (oracle-update-delivery (policy-id uint) (delivered bool) (on-time bool))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (oracle (var-get oracle-address))
    )
    (asserts! (is-some oracle) err-invalid-oracle)
    (asserts! (is-eq tx-sender (unwrap-panic oracle)) err-unauthorized)
    (asserts! (is-eq (get status policy) policy-status-active) err-invalid-policy)
    
    (if (and delivered on-time)
      (expire-policy policy-id)
      (begin
        (unwrap-panic (if (not delivered)
          (auto-claim policy-id u1 (get coverage-amount policy))
          (auto-claim policy-id u2 (/ (get coverage-amount policy) u2))
        ))
        (ok true)
      )
    )
  )
)

(define-private (auto-claim (policy-id uint) (claim-type uint) (amount uint))
  (let
    (
      (claim-id (+ (var-get claim-counter) u1))
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
    )
    (map-set claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        claimant: (get receiver policy),
        claim-type: claim-type,
        claim-amount: amount,
        status: claim-status-approved,
        submitted-at: stacks-block-height,
        processed-at: (some stacks-block-height),
        evidence: "oracle-automated"
      }
    )
    
    (var-set claim-counter claim-id)
    (try! (as-contract (stx-transfer? amount tx-sender (get receiver policy))))
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { status: policy-status-claimed })
    )
    
    (var-set total-locked-funds (- (var-get total-locked-funds) amount))
    (ok claim-id)
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-policy-premium (policy-id uint))
  (map-get? policy-premiums { policy-id: policy-id })
)

(define-read-only (get-contract-stats)
  {
    total-policies: (var-get policy-counter),
    total-claims: (var-get claim-counter),
    total-locked-funds: (var-get total-locked-funds),
    oracle-address: (var-get oracle-address)
  }
)

(define-read-only (calculate-premium (shipment-value uint) (route-risk uint))
  (let
    (
      (base-rate u5)
      (risk-multiplier (+ u100 (* route-risk u10)))
      (premium (/ (* shipment-value base-rate risk-multiplier) u10000))
    )
    premium
  )
)

(define-read-only (get-policy-status (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy (some (get status policy))
    none
  )
)

(define-read-only (is-policy-expired (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy (> stacks-block-height (get end-block policy))
    true
  )
)
