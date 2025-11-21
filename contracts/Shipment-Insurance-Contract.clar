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
(define-constant err-invalid-tier (err u109))
(define-constant err-notification-exists (err u110))
(define-constant err-notification-not-found (err u111))
(define-constant err-invalid-notification-type (err u112))
(define-constant err-invalid-transfer (err u113))
(define-constant err-transfer-not-authorized (err u114))

(define-constant policy-status-active u1)
(define-constant policy-status-claimed u2)
(define-constant policy-status-expired u3)
(define-constant policy-status-cancelled u4)

(define-constant claim-status-pending u1)
(define-constant claim-status-approved u2)
(define-constant claim-status-rejected u3)

(define-constant tier-bronze u1)
(define-constant tier-silver u2)
(define-constant tier-gold u3)
(define-constant tier-platinum u4)

(define-constant notification-type-policy-created u1)
(define-constant notification-type-policy-expired u2)
(define-constant notification-type-claim-submitted u3)
(define-constant notification-type-claim-approved u4)
(define-constant notification-type-claim-rejected u5)
(define-constant notification-type-delivery-confirmed u6)
(define-constant notification-type-policy-cancelled u7)
(define-constant notification-type-policy-transferred u8)

(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var total-locked-funds uint u0)
(define-data-var oracle-address (optional principal) none)
(define-data-var refund-rate uint u25)
(define-data-var max-discount-rate uint u30)
(define-data-var notification-counter uint u0)

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

(define-map refund-balances
  { user: principal }
  { refund-amount: uint }
)

(define-map user-loyalty-stats
  { user: principal }
  {
    successful-deliveries: uint,
    total-policies: uint,
    total-premium-paid: uint,
    current-tier: uint,
    last-updated: uint
  }
)

(define-map discount-tiers
  { tier: uint }
  {
    min-successful-deliveries: uint,
    min-total-policies: uint,
    discount-percentage: uint,
    tier-name: (string-ascii 20)
  }
)

(define-map stakeholder-subscriptions
  { stakeholder: principal, policy-id: uint }
  {
    notification-types: (list 10 uint),
    active: bool,
    subscribed-at: uint
  }
)

(define-map notifications
  { notification-id: uint }
  {
    policy-id: uint,
    notification-type: uint,
    stakeholder: principal,
    message: (string-ascii 100),
    created-at: uint,
    read: bool
  }
)

(define-map stakeholder-roles
  { stakeholder: principal }
  {
    role-type: (string-ascii 20),
    verified: bool,
    registered-at: uint
  }
)

(define-map policy-transfer-approvals
  { policy-id: uint, from: principal, to: principal }
  {
    approved: bool,
    initiated-at: uint,
    expires-at: uint
  }
)

(define-private (initialize-discount-tiers)
  (begin
    (map-set discount-tiers { tier: tier-bronze }
      {
        min-successful-deliveries: u0,
        min-total-policies: u0,
        discount-percentage: u0,
        tier-name: "Bronze"
      })
    (map-set discount-tiers { tier: tier-silver }
      {
        min-successful-deliveries: u3,
        min-total-policies: u5,
        discount-percentage: u10,
        tier-name: "Silver"
      })
    (map-set discount-tiers { tier: tier-gold }
      {
        min-successful-deliveries: u10,
        min-total-policies: u15,
        discount-percentage: u20,
        tier-name: "Gold"
      })
    (map-set discount-tiers { tier: tier-platinum }
      {
        min-successful-deliveries: u25,
        min-total-policies: u30,
        discount-percentage: u30,
        tier-name: "Platinum"
      })
    (ok true)
  )
)

(define-public (register-stakeholder (role-type (string-ascii 20)))
  (begin
    (map-set stakeholder-roles { stakeholder: tx-sender }
      {
        role-type: role-type,
        verified: false,
        registered-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (verify-stakeholder (stakeholder principal))
  (let
    (
      (role-info (unwrap! (map-get? stakeholder-roles { stakeholder: stakeholder }) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set stakeholder-roles { stakeholder: stakeholder }
      (merge role-info { verified: true })
    )
    (ok true)
  )
)

(define-public (subscribe-to-policy 
  (policy-id uint) 
  (notification-types (list 10 uint))
)
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (stakeholder-info (map-get? stakeholder-roles { stakeholder: tx-sender }))
    )
    (asserts! (is-some stakeholder-info) err-unauthorized)
    (asserts! (get verified (unwrap-panic stakeholder-info)) err-unauthorized)
    (asserts! (not (is-some (map-get? stakeholder-subscriptions { stakeholder: tx-sender, policy-id: policy-id }))) err-notification-exists)
    
    (map-set stakeholder-subscriptions { stakeholder: tx-sender, policy-id: policy-id }
      {
        notification-types: notification-types,
        active: true,
        subscribed-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (unsubscribe-from-policy (policy-id uint))
  (let
    (
      (subscription (unwrap! (map-get? stakeholder-subscriptions { stakeholder: tx-sender, policy-id: policy-id }) err-notification-not-found))
    )
    (map-set stakeholder-subscriptions { stakeholder: tx-sender, policy-id: policy-id }
      (merge subscription { active: false })
    )
    (ok true)
  )
)

(define-public (mark-notification-read (notification-id uint))
  (let
    (
      (notification (unwrap! (map-get? notifications { notification-id: notification-id }) err-notification-not-found))
    )
    (asserts! (is-eq tx-sender (get stakeholder notification)) err-unauthorized)
    (map-set notifications { notification-id: notification-id }
      (merge notification { read: true })
    )
    (ok true)
  )
)

(define-private (create-notification 
  (policy-id uint) 
  (notification-type uint) 
  (stakeholder principal) 
  (message (string-ascii 100))
)
  (let
    (
      (notification-id (+ (var-get notification-counter) u1))
    )
    (map-set notifications { notification-id: notification-id }
      {
        policy-id: policy-id,
        notification-type: notification-type,
        stakeholder: stakeholder,
        message: message,
        created-at: stacks-block-height,
        read: false
      }
    )
    (var-set notification-counter notification-id)
    notification-id
  )
)

(define-private (notify-stakeholders (policy-id uint) (notification-type uint) (message (string-ascii 100)))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
    )
    (create-notification policy-id notification-type (get shipper policy) message)
    (create-notification policy-id notification-type (get receiver policy) message)
    (ok true)
  )
)

(define-private (notify-subscribed-stakeholders (policy-id uint) (notification-type uint) (message (string-ascii 100)))
  (begin
    (unwrap-panic (notify-stakeholders policy-id notification-type message))
    (ok true)
  )
)

(define-public (set-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set oracle-address (some oracle))
    (map-set authorized-oracles { oracle: oracle } { active: true })
    (unwrap-panic (initialize-discount-tiers))
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
      (user-stats (default-to 
        { successful-deliveries: u0, total-policies: u0, total-premium-paid: u0, current-tier: tier-bronze, last-updated: u0 }
        (map-get? user-loyalty-stats { user: tx-sender })
      ))
      (discount-rate (get-user-discount tx-sender))
      (discounted-premium (- premium-amount (/ (* premium-amount discount-rate) u100)))
    )
    (asserts! (>= (stx-get-balance tx-sender) discounted-premium) err-insufficient-premium)
    (try! (stx-transfer? discounted-premium tx-sender (as-contract tx-sender)))
    
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
      { locked-amount: discounted-premium }
    )
    
    (map-set user-loyalty-stats { user: tx-sender }
      (merge user-stats {
        total-policies: (+ (get total-policies user-stats) u1),
        total-premium-paid: (+ (get total-premium-paid user-stats) discounted-premium),
        last-updated: stacks-block-height
      })
    )
    
    (var-set policy-counter policy-id)
    (var-set total-locked-funds (+ (var-get total-locked-funds) discounted-premium))
    (unwrap-panic (notify-stakeholders policy-id notification-type-policy-created "Policy created successfully"))
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
    (unwrap-panic (notify-stakeholders policy-id notification-type-claim-submitted "New claim submitted"))
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
        (unwrap-panic (notify-stakeholders policy-id notification-type-claim-approved "Claim approved and processed"))
      )
      (begin
        (map-set claims
          { claim-id: claim-id }
          (merge claim { 
            status: claim-status-rejected,
            processed-at: (some stacks-block-height)
          })
        )
        (unwrap-panic (notify-stakeholders policy-id notification-type-claim-rejected "Claim has been rejected"))
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
    (unwrap-panic (notify-stakeholders policy-id notification-type-policy-cancelled "Policy has been cancelled"))
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
    (unwrap-panic (notify-stakeholders policy-id notification-type-policy-expired "Policy has expired"))
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
      (begin
        (try! (process-successful-delivery policy-id))
        (unwrap-panic (notify-stakeholders policy-id notification-type-delivery-confirmed "Delivery confirmed successfully"))
        (expire-policy policy-id)
      )
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

(define-private (process-successful-delivery (policy-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (premium-info (unwrap! (map-get? policy-premiums { policy-id: policy-id }) err-not-found))
      (refund-amount (/ (* (get locked-amount premium-info) (var-get refund-rate)) u100))
      (current-refund (default-to u0 (get refund-amount (map-get? refund-balances { user: (get shipper policy) }))))
      (shipper (get shipper policy))
      (user-stats (default-to 
        { successful-deliveries: u0, total-policies: u0, total-premium-paid: u0, current-tier: tier-bronze, last-updated: u0 }
        (map-get? user-loyalty-stats { user: shipper })
      ))
      (new-successful-deliveries (+ (get successful-deliveries user-stats) u1))
      (new-tier (calculate-user-tier shipper new-successful-deliveries (get total-policies user-stats)))
    )
    (map-set refund-balances 
      { user: shipper }
      { refund-amount: (+ current-refund refund-amount) }
    )
    (map-set user-loyalty-stats { user: shipper }
      (merge user-stats {
        successful-deliveries: new-successful-deliveries,
        current-tier: new-tier,
        last-updated: stacks-block-height
      })
    )
    (ok refund-amount)
  )
)

(define-private (calculate-user-tier (user principal) (successful-deliveries uint) (total-policies uint))
  (if (and (>= successful-deliveries u25) (>= total-policies u30))
    tier-platinum
    (if (and (>= successful-deliveries u10) (>= total-policies u15))
      tier-gold
      (if (and (>= successful-deliveries u3) (>= total-policies u5))
        tier-silver
        tier-bronze
      )
    )
  )
)

(define-read-only (get-user-discount (user principal))
  (let
    (
      (user-stats (map-get? user-loyalty-stats { user: user }))
    )
    (match user-stats
      stats
        (let ((tier-info (unwrap! (map-get? discount-tiers { tier: (get current-tier stats) }) u0)))
          (get discount-percentage tier-info)
        )
      u0
    )
  )
)

(define-public (update-discount-tier (tier uint) (min-deliveries uint) (min-policies uint) (discount uint) (name (string-ascii 20)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= tier tier-bronze) (<= tier tier-platinum)) err-invalid-tier)
    (asserts! (<= discount (var-get max-discount-rate)) err-invalid-policy)
    (map-set discount-tiers { tier: tier }
      {
        min-successful-deliveries: min-deliveries,
        min-total-policies: min-policies,
        discount-percentage: discount,
        tier-name: name
      }
    )
    (ok true)
  )
)

(define-public (set-max-discount-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u50) err-invalid-policy)
    (var-set max-discount-rate new-rate)
    (ok true)
  )
)

(define-public (set-refund-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u100) err-invalid-policy)
    (var-set refund-rate new-rate)
    (ok true)
  )
)

(define-public (withdraw-refund)
  (let
    (
      (user-refund (unwrap! (map-get? refund-balances { user: tx-sender }) err-not-found))
      (refund-amount (get refund-amount user-refund))
    )
    (asserts! (> refund-amount u0) err-not-found)
    (try! (as-contract (stx-transfer? refund-amount tx-sender tx-sender)))
    (map-delete refund-balances { user: tx-sender })
    (ok refund-amount)
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

(define-read-only (get-refund-balance (user principal))
  (map-get? refund-balances { user: user })
)

(define-read-only (get-refund-rate)
  (var-get refund-rate)
)

(define-read-only (get-user-loyalty-stats (user principal))
  (map-get? user-loyalty-stats { user: user })
)

(define-read-only (get-discount-tier-info (tier uint))
  (map-get? discount-tiers { tier: tier })
)

(define-read-only (get-user-tier (user principal))
  (match (map-get? user-loyalty-stats { user: user })
    stats (some (get current-tier stats))
    none
  )
)

(define-read-only (calculate-discounted-premium (user principal) (base-premium uint))
  (let
    (
      (discount-rate (get-user-discount user))
      (discount-amount (/ (* base-premium discount-rate) u100))
    )
    {
      original-premium: base-premium,
      discount-rate: discount-rate,
      discount-amount: discount-amount,
      final-premium: (- base-premium discount-amount)
    }
  )
)

(define-read-only (get-max-discount-rate)
  (var-get max-discount-rate)
)

(define-read-only (get-notification (notification-id uint))
  (map-get? notifications { notification-id: notification-id })
)

(define-read-only (get-stakeholder-role (stakeholder principal))
  (map-get? stakeholder-roles { stakeholder: stakeholder })
)

(define-read-only (get-stakeholder-subscription (stakeholder principal) (policy-id uint))
  (map-get? stakeholder-subscriptions { stakeholder: stakeholder, policy-id: policy-id })
)

(define-read-only (get-notification-stats)
  {
    total-notifications: (var-get notification-counter),
    total-stakeholders: u0
  }
)

(define-public (initiate-policy-transfer (policy-id uint) (new-shipper principal) (transfer-duration uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (expires-at (+ stacks-block-height transfer-duration))
    )
    (asserts! (is-eq tx-sender (get shipper policy)) err-unauthorized)
    (asserts! (is-eq (get status policy) policy-status-active) err-invalid-policy)
    (asserts! (not (is-eq tx-sender new-shipper)) err-invalid-transfer)
    (asserts! (<= stacks-block-height (get end-block policy)) err-policy-expired)
    
    (map-set policy-transfer-approvals
      { policy-id: policy-id, from: tx-sender, to: new-shipper }
      {
        approved: false,
        initiated-at: stacks-block-height,
        expires-at: expires-at
      }
    )
    (ok true)
  )
)

(define-public (approve-policy-transfer (policy-id uint) (from-principal principal))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (transfer-request (unwrap! (map-get? policy-transfer-approvals { policy-id: policy-id, from: from-principal, to: tx-sender }) err-not-found))
    )
    (asserts! (is-eq (get status policy) policy-status-active) err-invalid-policy)
    (asserts! (<= stacks-block-height (get expires-at transfer-request)) err-policy-expired)
    (asserts! (is-eq from-principal (get shipper policy)) err-transfer-not-authorized)
    
    (map-set policy-transfer-approvals
      { policy-id: policy-id, from: from-principal, to: tx-sender }
      (merge transfer-request { approved: true })
    )
    (ok true)
  )
)

(define-public (execute-policy-transfer (policy-id uint) (to-principal principal))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (transfer-request (unwrap! (map-get? policy-transfer-approvals { policy-id: policy-id, from: tx-sender, to: to-principal }) err-not-found))
      (old-shipper-stats (default-to 
        { successful-deliveries: u0, total-policies: u0, total-premium-paid: u0, current-tier: tier-bronze, last-updated: u0 }
        (map-get? user-loyalty-stats { user: tx-sender })
      ))
      (new-shipper-stats (default-to 
        { successful-deliveries: u0, total-policies: u0, total-premium-paid: u0, current-tier: tier-bronze, last-updated: u0 }
        (map-get? user-loyalty-stats { user: to-principal })
      ))
    )
    (asserts! (is-eq tx-sender (get shipper policy)) err-unauthorized)
    (asserts! (is-eq (get status policy) policy-status-active) err-invalid-policy)
    (asserts! (get approved transfer-request) err-transfer-not-authorized)
    (asserts! (<= stacks-block-height (get expires-at transfer-request)) err-policy-expired)
    
    (map-set policies
      { policy-id: policy-id }
      (merge policy { shipper: to-principal })
    )
    
    (map-set user-loyalty-stats { user: tx-sender }
      (merge old-shipper-stats {
        total-policies: (if (> (get total-policies old-shipper-stats) u0) (- (get total-policies old-shipper-stats) u1) u0),
        last-updated: stacks-block-height
      })
    )
    
    (map-set user-loyalty-stats { user: to-principal }
      (merge new-shipper-stats {
        total-policies: (+ (get total-policies new-shipper-stats) u1),
        last-updated: stacks-block-height
      })
    )
    
    (map-delete policy-transfer-approvals { policy-id: policy-id, from: tx-sender, to: to-principal })
    (unwrap-panic (notify-stakeholders policy-id notification-type-policy-transferred "Policy ownership transferred"))
    (ok true)
  )
)

(define-public (cancel-policy-transfer (policy-id uint) (to-principal principal))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) err-not-found))
      (transfer-request (unwrap! (map-get? policy-transfer-approvals { policy-id: policy-id, from: tx-sender, to: to-principal }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get shipper policy)) err-unauthorized)
    (map-delete policy-transfer-approvals { policy-id: policy-id, from: tx-sender, to: to-principal })
    (ok true)
  )
)

(define-read-only (get-transfer-request (policy-id uint) (from-principal principal) (to-principal principal))
  (map-get? policy-transfer-approvals { policy-id: policy-id, from: from-principal, to: to-principal })
)
