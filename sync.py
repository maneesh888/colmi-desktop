#!/usr/bin/env python3
"""Simple Colmi ring sync using bleak"""
import asyncio
import json
import os
from datetime import datetime
from pathlib import Path

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    print("Installing bleak...")
    os.system("pip install bleak -q")
    from bleak import BleakClient, BleakScanner

SERVICE_UUID = "6e40fff0-b5a3-f393-e0a9-e50e24dcca9e"
RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # Write to ring
TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # Read from ring

response_data = None

def make_packet(cmd: int, payload: bytes = b"") -> bytes:
    """Create 16-byte packet with checksum"""
    packet = bytearray(16)
    packet[0] = cmd
    for i, b in enumerate(payload[:14]):
        packet[1 + i] = b
    packet[15] = sum(packet[:15]) % 256
    return bytes(packet)

def notification_handler(sender, data):
    global response_data
    response_data = data
    print(f"  📥 Received: {data.hex()}")

async def send_and_wait(client, data: bytes, wait_time: float = 2) -> bytes:
    global response_data
    response_data = None
    print(f"  📤 Sending: {data.hex()}")
    await client.write_gatt_char(RX_UUID, data, response=False)
    await asyncio.sleep(wait_time)
    return response_data

async def main():
    print("🔍 Scanning for Colmi ring...")
    
    # Try to find the ring
    ring = None
    devices = await BleakScanner.discover(timeout=10.0)
    for d in devices:
        name = d.name or ""
        if name.startswith("R0") or "colmi" in name.lower():
            ring = d
            print(f"✅ Found: {d.name} ({d.address})")
            break
    
    if not ring:
        print("❌ No Colmi ring found")
        return
    
    print(f"🔗 Connecting to {ring.name}...")
    
    async with BleakClient(ring.address) as client:
        print("✅ Connected!")
        
        # Subscribe to notifications
        await client.start_notify(TX_UUID, notification_handler)
        
        # Get battery
        print("\n🔋 Reading battery...")
        resp = await send_and_wait(client, make_packet(0x03))
        battery = resp[1] if resp else 0
        print(f"   Battery: {battery}%")
        
        # Start HR reading
        print("\n❤️ Reading heart rate (15 sec)...")
        hr_start = make_packet(0x69, bytes([0x01, 0x01]))
        resp = await send_and_wait(client, hr_start, wait_time=15)
        hr = 0
        if resp and resp[0] == 0x69 and resp[2] == 0:
            hr = resp[3]
        print(f"   Heart Rate: {hr} BPM")
        
        # Stop HR
        await send_and_wait(client, make_packet(0x6A, bytes([0x01, 0x00, 0x00])), wait_time=1)
        
        # Start SpO2 reading
        print("\n🫁 Reading SpO2 (15 sec)...")
        spo2_start = make_packet(0x69, bytes([0x03, 0x01]))
        resp = await send_and_wait(client, spo2_start, wait_time=15)
        spo2 = 0
        if resp and resp[0] == 0x69 and resp[2] == 0:
            spo2 = resp[3]
        print(f"   SpO2: {spo2}%")
        
        # Stop SpO2
        await send_and_wait(client, make_packet(0x6A, bytes([0x03, 0x00, 0x00])), wait_time=1)
        
        # Save to file
        health_dir = Path.home() / "clawd" / "health"
        health_dir.mkdir(parents=True, exist_ok=True)
        
        latest = {}
        latest_file = health_dir / "latest.json"
        if latest_file.exists():
            latest = json.loads(latest_file.read_text())
        
        now = datetime.utcnow().isoformat() + "Z"
        if battery > 0:
            latest["battery"] = battery
            latest["batteryTime"] = now
        if hr > 0:
            latest["heartRate"] = hr
            latest["heartRateTime"] = now
        if spo2 > 0:
            latest["spO2"] = spo2
            latest["spO2Time"] = now
        
        latest_file.write_text(json.dumps(latest, indent=2))
        print(f"\n✅ Saved to {latest_file}")
        print(json.dumps(latest, indent=2))

if __name__ == "__main__":
    asyncio.run(main())
