from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime
import json
import os
import csv

app = Flask(__name__)
CORS(app)

# CSV file configuration - should match slave EA's FolderName and FileName
CSV_FOLDER = "CopyTrader_0"  # Match the master's folder name
CSV_FILENAME = "signals.csv"

# MQL5 Files directory path
# MQL5 can only access files in: C:\Users\<username>\AppData\Roaming\MetaQuotes\Terminal\<TERMINAL_ID>\MQL5\Files\
from pathlib import Path
import glob

def get_mql5_files_path():
    """
    Find the MQL5 Files directory.
    Tries to find it automatically, or uses a configurable path.
    """
    # Option 1: Try to find automatically (look for any terminal ID)
    appdata_path = Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal"
    
    if appdata_path.exists():
        # Look for any terminal directory
        terminal_dirs = list(appdata_path.glob("*"))
        # Filter to directories that look like terminal IDs (32 char hex strings)
        terminal_dirs = [d for d in terminal_dirs if d.is_dir() and len(d.name) == 32]
        
        if terminal_dirs:
            # Use the first one found (or you can specify which one)
            terminal_id = terminal_dirs[0].name
            mql5_files = appdata_path / terminal_id / "MQL5" / "Files"
            if mql5_files.exists():
                print(f"📁 Found MQL5 Files directory: {mql5_files}")
                return str(mql5_files)
            else:
                # Create it if it doesn't exist
                mql5_files.mkdir(parents=True, exist_ok=True)
                print(f"📁 Created MQL5 Files directory: {mql5_files}")
                return str(mql5_files)
    
    # Option 2: Use specific terminal ID if you know it
    # Uncomment and set your terminal ID:
    # TERMINAL_ID = "D0E8209F77C8CF37AD8BF550E51FF075"  # From your log
    # mql5_files = appdata_path / TERMINAL_ID / "MQL5" / "Files"
    # if mql5_files.exists() or mql5_files.mkdir(parents=True, exist_ok=True):
    #     return str(mql5_files)
    
    # Option 3: Fallback to Documents (but this won't work with MQL5!)
    documents_path = Path.home() / "Documents"
    print(f"⚠️  WARNING: Could not find MQL5 Files directory, using Documents: {documents_path}")
    print(f"   This path will NOT be accessible from MQL5 EA!")
    print(f"   Please manually set the MQL5 Files path or terminal ID.")
    return str(documents_path)

# Setup paths
MQL5_FILES_PATH = get_mql5_files_path()
CSV_FOLDER_PATH = os.path.join(MQL5_FILES_PATH, CSV_FOLDER)
CSV_PATH = os.path.join(CSV_FOLDER_PATH, CSV_FILENAME)



def write_to_csv(data):
    try:
        # Create folder if it doesn't exist
        if not os.path.exists(CSV_FOLDER_PATH):
            os.makedirs(CSV_FOLDER_PATH)
            print(f"📁 Created folder: {CSV_FOLDER_PATH}")
        
        # Extract data fields (handle both lowercase and camelCase)
        time_str = data.get('time', data.get('Time', ''))
        ticket = data.get('ticket', data.get('Ticket', ''))
        symbol = data.get('symbol', data.get('Symbol', ''))
        type_str = data.get('type', data.get('Type', ''))
        action = data.get('action', data.get('Action', ''))
        volume = data.get('volume', data.get('Volume', 0))
        price = data.get('price', data.get('Price', 0))
        sl = data.get('sl', data.get('SL', 0))
        tp = data.get('tp', data.get('TP', 0))
        comment = data.get('comment', data.get('Comment', ''))
        
        # Check if file exists to determine if we need to write header
        file_exists = os.path.exists(CSV_PATH)
        
        # Open file in append mode
        with open(CSV_PATH, 'a', newline='', encoding='utf-8') as csvfile:
            writer = csv.writer(csvfile)
            
            # Write header if file is new
            if not file_exists:
                writer.writerow(['Time', 'Ticket', 'Symbol', 'Type', 'Action', 'Volume', 'Price', 'SL', 'TP', 'Comment', 'Slave_ticket'])
                print(f"📝 Created CSV file with header: {CSV_PATH}")
            
            # Write data row (Slave_ticket is empty for now)
            writer.writerow([
                time_str,
                ticket,
                symbol,
                type_str,
                action,
                volume,
                price,
                sl,
                tp,
                comment,
                ''  # Slave_ticket - empty for now
            ])
        
        print(f"✅ Written to CSV: {CSV_PATH}")
        print(f"   Row: {time_str}, {ticket}, {symbol}, {type_str}, {action}")
        
    except Exception as e:
        print(f"❌ Error writing to CSV: {e}")
        import traceback
        print(f"❌ Traceback: {traceback.format_exc()}")


@app.route('/CSV', methods=['POST'])
@app.route('/csv', methods=['POST'])  # Support both uppercase and lowercase
def csv_handler():
    try:
        # Get raw data first for debugging
        raw_data = request.get_data(as_text=True)
        
        print(f"📥 REQUEST RECEIVED ------------> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")       
        # Print raw data first
        print(f" 📦 Raw Request Data------------->:  {raw_data}")
        
        # Try to parse JSON
        data = None
        if request.is_json:
            data = request.get_json(force=True)
        else:
            # Try to parse manually if not detected as JSON
            try:
                if raw_data:
                    data = json.loads(raw_data)
            except json.JSONDecodeError as e:
                print(f"⚠️  JSON decode error: {e}")
        
        if data:
            print(f"   CSV Row: {data.get('csv', 'N/A')}")
            print(f"   Magic ID: {data.get('magic', data.get('MagicID', 'N/A'))}")
            print(f"   Time: {data.get('time', data.get('Time', 'N/A'))}")
            print(f"   Ticket: {data.get('ticket', data.get('Ticket', 'N/A'))}")
            print(f"   Symbol: {data.get('symbol', data.get('Symbol', 'N/A'))}")
            print(f"   Type: {data.get('type', data.get('Type', 'N/A'))}")
            print(f"   Action: {data.get('action', data.get('Action', 'N/A'))}")
            print(f"   Volume: {data.get('volume', data.get('Volume', 'N/A'))} lots")
            print(f"   Price: {data.get('price', data.get('Price', 'N/A'))}")
            print(f"   Stop Loss: {data.get('sl', data.get('SL', 'N/A'))}")
            print(f"   Take Profit: {data.get('tp', data.get('TP', 'N/A'))}")
            print(f"   Comment: {data.get('comment', data.get('Comment', 'N/A'))}")
            
            # Write to CSV file for slave EA to read
            write_to_csv(data)
        else:
            print("="*70)
            print("⚠️  No valid JSON data received")
            print(f"   Raw data type: {type(raw_data)}")
            print(f"   Raw data length: {len(raw_data) if raw_data else 0}")
            print("="*70)
        # Return success response with proper headers
        response = jsonify({"status": "ok", "message": "Data received successfully"})
        response.headers['Content-Type'] = 'application/json'
        print("✅ Sending 200 OK response\n")
        return response, 200
        
    except Exception as e:
        import traceback
        print(f"❌ Error processing request: {e}")
        print(f"❌ Traceback: {traceback.format_exc()}")
        return jsonify({"status": "error", "message": str(e)}), 400

if __name__ == '__main__':
    print("📡 Listening on: http://0.0.0.0:5000")
    print("📡 Endpoint: http://0.0.0.0:5000/CSV")
    print("="*70 + "\n")
    print("✅ Server ready! Waiting for requests from MQL5 EA...")
    print("   Press Ctrl+C to stop\n")
    
    # Use 0.0.0.0 to accept connections from external IPs (VPS)
    # Port 5000 to match the EA's TargetURL
    app.run(debug=False, host='127.0.0.1', port=5000)
