;; Revenue Optimization Contract
;; Analyzes parking usage patterns to optimize rates and time limits

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-INPUT (err u501))
(define-constant ERR-ZONE-NOT-FOUND (err u502))
(define-constant ERR-EXPERIMENT-NOT-FOUND (err u503))
(define-constant ERR-INVALID-RATE (err u504))

;; Data Variables
(define-data-var next-zone-id uint u1)
(define-data-var next-experiment-id uint u1)
(define-data-var total-revenue-tracked uint u0)

;; Data Maps
(define-map parking-zones
  { zone-id: uint }
  {
    name: (string-ascii 50),
    location: (string-ascii 100),
    current-rate: uint,
    time-limit: uint,
    capacity: uint,
    zone-type: (string-ascii 20)
  }
)

(define-map usage-analytics
  { zone-id: uint, date: uint }
  {
    total-sessions: uint,
    average-duration: uint,
    peak-occupancy: uint,
    revenue-generated: uint,
    compliance-rate: uint
  }
)

(define-map rate-experiments
  { experiment-id: uint }
  {
    zone-id: uint,
    experiment-name: (string-ascii 50),
    old-rate: uint,
    new-rate: uint,
    start-date: uint,
    end-date: uint,
    status: (string-ascii 15),
    revenue-impact: int,
    usage-impact: int
  }
)

(define-map optimization-recommendations
  { zone-id: uint }
  {
    recommended-rate: uint,
    recommended-time-limit: uint,
    confidence-score: uint,
    last-updated: uint,
    reasoning: (string-ascii 200)
  }
)

(define-map analysts
  { analyst-id: (string-ascii 20) }
  {
    name: (string-ascii 50),
    active: bool,
    experiments-run: uint
  }
)

;; Authorization Functions
(define-public (add-analyst
  (analyst-id (string-ascii 20))
  (name (string-ascii 50))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set analysts
      { analyst-id: analyst-id }
      {
        name: name,
        active: true,
        experiments-run: u0
      }
    ))
  )
)

;; Zone Management Functions
(define-public (create-parking-zone
  (name (string-ascii 50))
  (location (string-ascii 100))
  (initial-rate uint)
  (time-limit uint)
  (capacity uint)
  (zone-type (string-ascii 20))
)
  (let
    (
      (zone-id (var-get next-zone-id))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> initial-rate u0) ERR-INVALID-INPUT)
    (asserts! (< initial-rate u10000) ERR-INVALID-RATE)
    (asserts! (> time-limit u0) ERR-INVALID-INPUT)
    (asserts! (> capacity u0) ERR-INVALID-INPUT)

    (map-set parking-zones
      { zone-id: zone-id }
      {
        name: name,
        location: location,
        current-rate: initial-rate,
        time-limit: time-limit,
        capacity: capacity,
        zone-type: zone-type
      }
    )
    (var-set next-zone-id (+ zone-id u1))
    (ok zone-id)
  )
)

;; Analytics Functions
(define-public (record-usage-data
  (zone-id uint)
  (date uint)
  (total-sessions uint)
  (average-duration uint)
  (peak-occupancy uint)
  (revenue-generated uint)
  (compliance-rate uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? parking-zones { zone-id: zone-id })) ERR-ZONE-NOT-FOUND)
    (asserts! (<= compliance-rate u100) ERR-INVALID-INPUT)

    (map-set usage-analytics
      { zone-id: zone-id, date: date }
      {
        total-sessions: total-sessions,
        average-duration: average-duration,
        peak-occupancy: peak-occupancy,
        revenue-generated: revenue-generated,
        compliance-rate: compliance-rate
      }
    )
    (var-set total-revenue-tracked (+ (var-get total-revenue-tracked) revenue-generated))
    (ok true)
  )
)

;; Rate Optimization Functions
(define-public (start-rate-experiment
  (zone-id uint)
  (experiment-name (string-ascii 50))
  (new-rate uint)
  (duration-days uint)
  (analyst-id (string-ascii 20))
)
  (let
    (
      (experiment-id (var-get next-experiment-id))
      (zone-data (unwrap! (map-get? parking-zones { zone-id: zone-id }) ERR-ZONE-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (end-time (+ current-time (* duration-days u86400)))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-analyst-active analyst-id) ERR-NOT-AUTHORIZED)
    (asserts! (> new-rate u0) ERR-INVALID-INPUT)
    (asserts! (< new-rate u10000) ERR-INVALID-RATE)
    (asserts! (> duration-days u0) ERR-INVALID-INPUT)
    (asserts! (<= duration-days u90) ERR-INVALID-INPUT)

    (map-set rate-experiments
      { experiment-id: experiment-id }
      {
        zone-id: zone-id,
        experiment-name: experiment-name,
        old-rate: (get current-rate zone-data),
        new-rate: new-rate,
        start-date: current-time,
        end-date: end-time,
        status: "active",
        revenue-impact: 0,
        usage-impact: 0
      }
    )

    ;; Update zone rate
    (map-set parking-zones
      { zone-id: zone-id }
      (merge zone-data { current-rate: new-rate })
    )

    ;; Update analyst stats
    (match (map-get? analysts { analyst-id: analyst-id })
      analyst-data (map-set analysts
        { analyst-id: analyst-id }
        (merge analyst-data { experiments-run: (+ (get experiments-run analyst-data) u1) })
      )
      false
    )

    (var-set next-experiment-id (+ experiment-id u1))
    (ok experiment-id)
  )
)

(define-public (end-experiment
  (experiment-id uint)
  (revenue-impact int)
  (usage-impact int)
)
  (let
    (
      (experiment-data (unwrap! (map-get? rate-experiments { experiment-id: experiment-id }) ERR-EXPERIMENT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status experiment-data) "active") ERR-INVALID-INPUT)

    (map-set rate-experiments
      { experiment-id: experiment-id }
      (merge experiment-data {
        status: "completed",
        revenue-impact: revenue-impact,
        usage-impact: usage-impact
      })
    )
    (ok true)
  )
)

(define-public (generate-optimization-recommendation
  (zone-id uint)
  (recommended-rate uint)
  (recommended-time-limit uint)
  (confidence-score uint)
  (reasoning (string-ascii 200))
)
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? parking-zones { zone-id: zone-id })) ERR-ZONE-NOT-FOUND)
    (asserts! (> recommended-rate u0) ERR-INVALID-INPUT)
    (asserts! (< recommended-rate u10000) ERR-INVALID-RATE)
    (asserts! (<= confidence-score u100) ERR-INVALID-INPUT)

    (map-set optimization-recommendations
      { zone-id: zone-id }
      {
        recommended-rate: recommended-rate,
        recommended-time-limit: recommended-time-limit,
        confidence-score: confidence-score,
        last-updated: current-time,
        reasoning: reasoning
      }
    )
    (ok true)
  )
)

(define-public (apply-recommendation (zone-id uint))
  (let
    (
      (zone-data (unwrap! (map-get? parking-zones { zone-id: zone-id }) ERR-ZONE-NOT-FOUND))
      (recommendation (unwrap! (map-get? optimization-recommendations { zone-id: zone-id }) ERR-INVALID-INPUT))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get confidence-score recommendation) u70) ERR-INVALID-INPUT)

    (map-set parking-zones
      { zone-id: zone-id }
      (merge zone-data {
        current-rate: (get recommended-rate recommendation),
        time-limit: (get recommended-time-limit recommendation)
      })
    )
    (ok true)
  )
)

;; Query Functions
(define-read-only (get-parking-zone (zone-id uint))
  (map-get? parking-zones { zone-id: zone-id })
)

(define-read-only (get-usage-analytics (zone-id uint) (date uint))
  (map-get? usage-analytics { zone-id: zone-id, date: date })
)

(define-read-only (get-experiment (experiment-id uint))
  (map-get? rate-experiments { experiment-id: experiment-id })
)

(define-read-only (get-recommendation (zone-id uint))
  (map-get? optimization-recommendations { zone-id: zone-id })
)

(define-read-only (is-analyst-active (analyst-id (string-ascii 20)))
  (match (map-get? analysts { analyst-id: analyst-id })
    analyst-data (get active analyst-data)
    false
  )
)

(define-read-only (get-total-revenue-tracked)
  (var-get total-revenue-tracked)
)

(define-read-only (calculate-zone-efficiency (zone-id uint))
  (let
    (
      (zone-data (unwrap! (map-get? parking-zones { zone-id: zone-id }) (err u0)))
      (current-date (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (match (map-get? usage-analytics { zone-id: zone-id, date: current-date })
      analytics (ok {
        occupancy-rate: (/ (* (get peak-occupancy analytics) u100) (get capacity zone-data)),
        revenue-per-space: (/ (get revenue-generated analytics) (get capacity zone-data)),
        compliance-rate: (get compliance-rate analytics)
      })
      (err u0)
    )
  )
)
