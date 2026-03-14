# Clawdbot Integration Plan

## Overview

Colmi Desktop syncs health data to `~/clawd/health/`. Clawdbot reads this data and provides AI-powered health insights.

## Data Flow

```
Colmi Ring → Colmi Desktop → ~/clawd/health/*.json → Clawdbot Skill → User
```

## Data Files

### Current Structure
```
~/clawd/health/
├── latest.json           # Most recent readings
├── heart_rate/
│   └── YYYY-MM-DD.json   # Daily HR logs (288 readings/day)
├── spo2/
│   └── YYYY-MM-DD.json   # Daily SpO2 logs
├── activity/
│   └── YYYY-MM-DD.json   # Steps, calories, distance
├── sleep/
│   └── YYYY-MM-DD.json   # Sleep sessions
└── stress/
    └── YYYY-MM-DD.json   # Stress readings
```

### latest.json Schema
```json
{
  "timestamp": "2026-03-14T23:00:00Z",
  "heartRate": 72,
  "spo2": 98,
  "battery": 85,
  "steps": 8432,
  "calories": 342,
  "ringConnected": true
}
```

### heart_rate/YYYY-MM-DD.json Schema
```json
{
  "date": "2026-03-14",
  "readings": [
    {"time": "00:00", "bpm": 62},
    {"time": "00:05", "bpm": 58},
    ...
  ],
  "stats": {
    "min": 52,
    "max": 145,
    "avg": 71,
    "resting": 58
  }
}
```

## Clawdbot Skill

### Skill Location
`~/.clawdbot/skills/health-ring/`

### SKILL.md
```markdown
# Health Ring Skill

Read and analyze health data from Colmi smart ring.

## Commands

- "How's my heart rate?" — Current + today's trend
- "How did I sleep?" — Last night's sleep analysis
- "Health summary" — Daily overview
- "Any health concerns?" — Anomaly check

## Data Source
~/clawd/health/
```

### Capabilities

1. **Current Status**
   - Real-time HR, SpO2, battery
   - Ring connection status

2. **Daily Summaries**
   - Resting heart rate
   - Average SpO2
   - Total steps/calories
   - Sleep duration & quality

3. **Trend Analysis**
   - Week-over-week comparisons
   - Anomaly detection
   - Recovery tracking

4. **Proactive Alerts**
   - Unusual resting HR
   - Low SpO2 readings
   - Poor sleep quality
   - Stress patterns

## Cron Jobs

### Morning Briefing
```
0 7 * * * — "Good morning! Here's your health summary from last night..."
```

### Anomaly Check
```
0 */4 * * * — Check for unusual readings, alert if found
```

## Natural Language Queries

| Query | Response |
|-------|----------|
| "How was my sleep?" | Sleep duration, quality score, wake events |
| "What's my resting heart rate?" | Current RHR + 7-day trend |
| "Am I stressed?" | Stress readings + HRV analysis |
| "How active was I today?" | Steps, calories, active minutes |
| "Any health issues?" | Anomaly scan + recommendations |

## Implementation Steps

1. [ ] Create skill folder structure
2. [ ] Write SKILL.md with commands
3. [ ] Create data reader script
4. [ ] Add to Clawdbot skills
5. [ ] Set up cron jobs for summaries
6. [ ] Test queries

## Example Interaction

**User:** How did I sleep last night?

**Clawdbot:** 
> 😴 **Sleep Summary — March 14**
> 
> **Duration:** 6h 42m (11:30 PM → 6:12 AM)
> **Quality:** 73/100 — Fair
> 
> - Deep sleep: 1h 15m (19%)
> - Light sleep: 4h 20m (65%)
> - Awake: 1h 07m (3 wake events)
> 
> Your resting HR was 54 bpm — normal for you.
> 
> 💡 You had a late bedtime. Aiming for 10:30 PM could improve deep sleep.
