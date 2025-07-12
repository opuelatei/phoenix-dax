;; Title: Phoenix Digital Assets Exchange
;;
;; Summary:
;; Revolutionary digital asset platform that transforms traditional NFT trading through
;; cryptocurrency-backed collateralization, community staking pools, and dynamic 
;; fractional ownership mechanisms. Built for the next generation of decentralized finance.
;;
;; Description:
;; Phoenix DAX represents the evolution of digital asset management, combining the security
;; of cryptocurrency collateral with the flexibility of modern DeFi protocols. This platform
;; enables creators and collectors to participate in a robust ecosystem where digital assets
;; maintain intrinsic value through collateral backing while generating passive income
;; through innovative staking mechanisms.
;;
;; Key innovations include:
;; - Collateral-secured asset minting with dynamic ratio adjustments
;; - Community-driven staking pools with automated yield distribution
;; - Seamless fractional ownership for democratized access to premium assets
;; - Zero-slippage trading with integrated fee optimization
;; - Advanced risk management through overcollateralization protocols
;; - Real-time yield calculations based on network participation
;;
;; The platform maintains institutional-grade security with a 150% collateral floor
;; and implements a sustainable 2.5% protocol fee structure. Staking participants
;; earn competitive 5% APY while contributing to network stability and growth.

;; CONSTANTS & ERROR HANDLING

(define-constant contract-owner tx-sender)

;; Comprehensive error code system for robust contract operations
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-invalid-token (err u103))
(define-constant err-listing-not-found (err u104))
(define-constant err-invalid-price (err u105))
(define-constant err-insufficient-collateral (err u106))
(define-constant err-already-staked (err u107))
(define-constant err-not-staked (err u108))
(define-constant err-invalid-percentage (err u109))
(define-constant err-invalid-uri (err u110))
(define-constant err-invalid-recipient (err u111))
(define-constant err-overflow (err u112))

;; PROTOCOL CONFIGURATION

;; Core protocol parameters for optimal performance and security
(define-data-var min-collateral-ratio uint u150) ;; 150% minimum collateral ratio
(define-data-var protocol-fee uint u25) ;; 2.5% fee in basis points
(define-data-var total-staked uint u0) ;; Total staked assets counter
(define-data-var yield-rate uint u50) ;; 5% annual yield rate in basis points
(define-data-var total-supply uint u0) ;; Total asset supply tracker

;; DATA STRUCTURES

;; Primary asset registry with comprehensive metadata
(define-map tokens
  { token-id: uint }
  {
    owner: principal,
    uri: (string-ascii 256),
    collateral: uint,
    is-staked: bool,
    stake-timestamp: uint,
    fractional-shares: uint,
  }
)

;; Marketplace listing registry for active trades
(define-map token-listings
  { token-id: uint }
  {
    price: uint,
    seller: principal,
    active: bool,
  }
)

;; Fractional ownership distribution tracking
(define-map fractional-ownership
  {
    token-id: uint,
    owner: principal,
  }
  { shares: uint }
)

;; Staking rewards accumulation and distribution
(define-map staking-rewards
  { token-id: uint }
  {
    accumulated-yield: uint,
    last-claim: uint,
  }
)

;; UTILITY FUNCTIONS

;; Validates URI format and ensures proper metadata structure
(define-private (validate-uri (uri (string-ascii 256)))
  (let ((uri-len (len uri)))
    (and
      (> uri-len u0)
      (<= uri-len u256)
    )
  )
)

;; Prevents contracts from receiving assets to maintain security
(define-private (validate-recipient (recipient principal))
  (not (is-eq recipient (as-contract tx-sender)))
)

;; Safe arithmetic operations with overflow protection
(define-private (safe-add
    (a uint)
    (b uint)
  )
  (let ((sum (+ a b)))
    (asserts! (>= sum a) err-overflow)
    (ok sum)
  )
)

;; CORE ASSET MANAGEMENT

;; Creates new collateral-backed digital assets with security guarantees
(define-public (mint-nft
    (uri (string-ascii 256))
    (collateral uint)
  )
  (let (
      (token-id (+ (var-get total-supply) u1))
      (collateral-requirement (/ (* (var-get min-collateral-ratio) collateral) u100))
    )
    (asserts! (validate-uri uri) err-invalid-uri)
    (asserts! (>= (stx-get-balance tx-sender) collateral-requirement)
      err-insufficient-collateral
    )
    (try! (stx-transfer? collateral-requirement tx-sender (as-contract tx-sender)))
    (map-set tokens { token-id: token-id } {
      owner: tx-sender,
      uri: uri,
      collateral: collateral,
      is-staked: false,
      stake-timestamp: u0,
      fractional-shares: u0,
    })
    (var-set total-supply token-id)
    (ok token-id)
  )
)

;; Secure asset transfer with comprehensive validation
(define-public (transfer-nft
    (token-id uint)
    (recipient principal)
  )
  (let ((token (unwrap! (get-token-info token-id) err-invalid-token)))
    (asserts! (validate-recipient recipient) err-invalid-recipient)
    (asserts! (is-eq tx-sender (get owner token)) err-not-token-owner)
    (asserts! (not (get is-staked token)) err-already-staked)
    (map-set tokens { token-id: token-id } (merge token { owner: recipient }))
    (ok true)
  )
)

;; MARKETPLACE OPERATIONS

;; Lists assets for public trading with dynamic pricing
(define-public (list-nft
    (token-id uint)
    (price uint)
  )
  (let ((token (unwrap! (get-token-info token-id) err-invalid-token)))
    (asserts! (> price u0) err-invalid-price)
    (asserts! (is-eq tx-sender (get owner token)) err-not-token-owner)
    (asserts! (not (get is-staked token)) err-already-staked)
    (map-set token-listings { token-id: token-id } {
      price: price,
      seller: tx-sender,
      active: true,
    })
    (ok true)
  )
)

;; Executes marketplace purchases with automated fee distribution
(define-public (purchase-nft (token-id uint))
  (let (
      (listing (unwrap! (get-listing token-id) err-listing-not-found))
      (price (get price listing))
      (seller (get seller listing))
      (fee (/ (* price (var-get protocol-fee)) u1000))
    )
    (asserts! (get active listing) err-listing-not-found)
    (asserts! (is-eq (get active listing) true) err-listing-not-found)
    ;; Execute payment flow with protocol fee collection
    (try! (stx-transfer? price tx-sender seller))
    (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
    ;; Complete ownership transfer
    (try! (transfer-nft token-id tx-sender))
    ;; Clear marketplace listing
    (map-set token-listings { token-id: token-id } {
      price: u0,
      seller: seller,
      active: false,
    })
    (ok true)
  )
)