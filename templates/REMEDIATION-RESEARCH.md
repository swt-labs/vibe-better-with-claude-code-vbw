---
phase: {NN} # bare integer, no quotes
round: {RR} # remediation round number, bare integer
title: {research-title}
type: remediation-research
confidence: {high|medium|low}
date: {YYYY-MM-DD}
---

# Phase {phase_number}: {phase_name} — Remediation Research (Round {RR})

## Findings

{What is actually failing and why — per-issue analysis of UAT failures}

## Prior Fix Analysis

{Why previous fix attempts failed — what was tried, why it didn't work, what was missed}

## Root Cause Assessment

{Per-issue root cause analysis — distinguish symptoms from underlying causes}

## Recommendations

{Suggested fix approaches, ranked by recurring failure count — prioritize issues that resisted multiple rounds}
