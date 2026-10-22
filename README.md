# Quant-BTC-DEMAC-Engine
# Quantitative BTC Directional Allocation Engine (10/20 DEMAC Reversal System)

[![Python 3.10+](https://img.shields.io/badge/python-3.10%2B-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

This repository contains a quantitative, always-in-market systematic execution strategy designed for daily Bitcoin (`BTC/USD`) price discovery. The engine operates a **Dual-Exponential Moving Average Convergence/Divergence (10/20 DEMAC)** continuous state machine.

The system maintains 100% directional exposure—seamlessly executing automated reversals between long exposure and short/flat hedging upon multi-period exponential trend intersections. By pairing a rapid 10-period micro-trend vector with a 20-period baseline trend vector, the model minimizes signal lag while filtering micro-structure noise.

---

## Model Architecture & Execution Logic

The execution framework evaluates closing prices at discrete daily intervals ($t$) and calculates short-term vs. medium-term momentum dynamics.

### Mathematical Formulation

The Exponential Moving Average ($\text{EMA}$) at interval $t$ with lookback period $N$ is defined as:

$$\text{EMA}_t = \left( P_t \times \alpha \right) + \left( \text{EMA}_{t-1} \times (1 - \alpha) \right) \quad \text{where} \quad \alpha = \frac{2}{N + 1}$$

The strategy monitors the spread between the Fast Vector ($N=10$) and the Slow Vector ($N=20$):

$$\text{Spread}_t = \mathbf{EMA}_{10}(t) - \mathbf{EMA}_{20}(t)$$

### State Transition & Reversal Matrix

The system continuously transitions between binary allocation states based on spread sign changes[cite: 1]:

                        Spread Axis
                             │
     Bullish Inflection      │     Bearish Inflection
   (Spread Crosses > 0)      │    (Spread Crosses < 0)
─────────────────────────────┼─────────────────────────────>
   State: +1 (Long Position) │   State: -1 (Short / Flat)

1. **Bullish Reversal / Long Entry ($\mathbb{S}_t = +1$):**  
   Issued when $\text{Spread}_{t} > 0$ and $\text{Spread}_{t-1} \le 0$[cite: 1]. The active Short position is automatically liquidated, and an equivalent Long position is initiated at the open of bar $t+1$[cite: 1].

2. **Bearish Reversal / Short Entry ($\mathbb{S}_t = -1$):**  
   Issued when $\text{Spread}_{t} < 0$ and $\text{Spread}_{t-1} \ge 0$[cite: 1]. The active Long position is automatically liquidated, and an equivalent Short/Flat position is initiated at the open of bar $t+1$[cite: 1].

---

## Strategy Parameters

| Parameter Key | Typology | Value | Description |
| :--- | :--- | :--- | :--- |
| `ASSET_TICKER` | `String` | `"BTC/USD"` | Target digital asset pair[cite: 1] |
| `TIMEFRAME` | `Resolution` | `"1D"` | Daily aggregation window[cite: 1] |
| `FAST_EMA_PERIOD` | `Integer` | `10` | Fast micro-trend exponential lookback[cite: 1] |
| `SLOW_EMA_PERIOD` | `Integer` | `20` | Slow macro-trend exponential lookback[cite: 1] |
| `ALLOCATION_MODE` | `State` | `Continuous Reversal` | Always-in-market state switching |
| `EXECUTION_OFFSET` | `Integer` | `1` | Next-bar open execution to prevent look-ahead bias[cite: 1] |

---

## Quick Start & Usage

### 1. Installation

```bash
# Clone repository
git clone [https://github.com/your-username/Quant-BTC-DEMAC-Engine.git](https://github.com/your-username/Quant-BTC-DEMAC-Engine.git)
cd Quant-BTC-DEMAC-Engine

# Create virtual environment & install requirements
python -m venv venv
source venv/bin/activate  # On Windows use: venv\Scripts\activate
pip install -r requirements.txt

# for backtest - bash:
python main.py --symbol BTC/USD --timeframe 1D --fast 10 --slow 20

