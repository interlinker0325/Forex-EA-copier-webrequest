//+------------------------------------------------------------------+
//|                                                         wwwww.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

input double PollInterval = 1;  // Polling interval in seconds (0.1 = 100ms, 1.0 = 1 second)
input string CSVPath = "CopyTrader_0/signals.csv";  // Relative path from MQL5 Files directory (use forward slashes)
input int SlaveMagicID = 123456;  // Magic ID for slave trades
input int SlippagePoints = 10;  // Maximum slippage in points

int lastProcessedLineCount = 0;  // Track last processed line count
bool fileExists = false;  // Track if file exists
datetime lastFileModTime = 0;  // Track file modification time
long lastFileSize = 0;  // Track file size
int timerCallCount = 0;  // Debug: count timer calls

// Cache for master ticket -> slave ticket mappings (to avoid CSV file locking issues)
struct TicketMapping
  {
   ulong masterTicket;
   ulong slaveTicket;
   string symbol;
   datetime openTime;
  };
TicketMapping ticketCache[];  // In-memory cache for ticket mappings

//+------------------------------------------------------------------+
//| Check if path is absolute (starts with drive letter)             |
//+------------------------------------------------------------------+
bool IsAbsolutePath(string path)
  {
   if(StringLen(path) < 2) return false;
   // Check for Windows drive letter pattern: C:/ or C:\
   ushort firstChar = StringGetCharacter(path, 0);
   ushort secondChar = StringGetCharacter(path, 1);
   return ((firstChar >= 'A' && firstChar <= 'Z') || (firstChar >= 'a' && firstChar <= 'z')) && 
          (secondChar == ':' || secondChar == '/' || secondChar == '\\');
  }
//+------------------------------------------------------------------+
//| Extract relative path from absolute path                         |
//+------------------------------------------------------------------+
string ExtractRelativePath(string absolutePath)
  {
   string normalized = absolutePath;
   StringReplace(normalized, "\\", "/");
   
   // Look for "CopyTrader" folder in the path
   int pos = StringFind(normalized, "CopyTrader");
   if(pos >= 0)
     {
      return StringSubstr(normalized, pos);
     }
   
   // If CopyTrader not found, try to get the last folder + filename
   // Find last slash
   int lastSlash = -1;
   for(int i = StringLen(normalized) - 1; i >= 0; i--)
     {
      if(StringGetCharacter(normalized, i) == '/')
        {
         lastSlash = i;
         break;
         }
      }
   
   if(lastSlash > 0)
     {
      // Find second-to-last slash to get folder + filename
      int secondLastSlash = -1;
      for(int i = lastSlash - 1; i >= 0; i--)
        {
         if(StringGetCharacter(normalized, i) == '/')
           {
            secondLastSlash = i;
            break;
            }
         }
      
      if(secondLastSlash >= 0)
         return StringSubstr(normalized, secondLastSlash + 1);
      else
         return StringSubstr(normalized, lastSlash + 1);
     }
   
   // Fallback: return just the filename if no slashes found
   return normalized;
  }
//+------------------------------------------------------------------+
//| Normalize path to use forward slashes (MQL5 requirement)         |
//+------------------------------------------------------------------+
string NormalizePath(string path)
  {
   // Check if it's an absolute path
   if(IsAbsolutePath(path))
     {
      // Extract relative part from absolute path
      string relative = ExtractRelativePath(path);
      path = relative;
     }
   
   string result = path;
   StringReplace(result, "\\", "/");
   // Remove leading slashes if present
   while(StringLen(result) > 0 && StringGetCharacter(result, 0) == '/')
      result = StringSubstr(result, 1);
   return result;
  }
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   Print("========================================");
   Print(">>> CSV MONITOR EA INITIALIZING <<<");
   Print("========================================");
   if(PollInterval < 1.0)
     {
      Print("  Poll Interval: ", (int)(PollInterval * 1000), " ms (", DoubleToString(PollInterval, 3), " seconds)");
     }
   else
     {
      Print("  Poll Interval: ", DoubleToString(PollInterval, 1), " second(s)");
     }
   
   // Check if absolute path was provided and warn user
   if(IsAbsolutePath(CSVPath))
     {
      Print("  ⚠️  WARNING: Absolute path detected!");
      Print("  ⚠️  MQL5 can only access files in its Files directory!");
      Print("  ⚠️  Will extract relative path from absolute path");
     }
   
   // Normalize path to use forward slashes
   string normalizedPath = NormalizePath(CSVPath);
   string expectedFullPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + normalizedPath;
   Print("  Normalized Path: ", normalizedPath);
   Print("  Full Path: ", expectedFullPath);
   Print("  NOTE: MQL5 can only access files in its Files directory!");
   Print("========================================");
   
   // Check if file exists
   bool exists = CheckFileExists(normalizedPath);
   if(exists)
     {
      fileExists = true;
      Print("  ✓ CSV file found and accessible!");
      
      // Get initial file stats
      GetFileStats(normalizedPath);
      
      // Count initial lines to set baseline
      lastProcessedLineCount = CountCSVLines(normalizedPath);
      Print("  Initial line count: ", lastProcessedLineCount);
      Print("  Initial file size: ", lastFileSize, " bytes");
      if(lastFileModTime > 0)
         Print("  Initial mod time: ", TimeToString(lastFileModTime, TIME_DATE|TIME_SECONDS));
     }
   else
     {
      fileExists = false;
      Print("  ⚠ CSV file not found!");
      Print("  Expected location: ", expectedFullPath);
      Print("  ========================================");
      Print("  TROUBLESHOOTING:");
      Print("  1. Set CSVPath = \"CopyTrader_0/signals.csv\" (use forward slashes)");
      Print("  2. Make sure Python script writes to MQL5 Files directory");
      Print("  3. Check that the file exists at the expected location");
      Print("  4. Remove EA from chart and re-add to reset inputs");
      Print("  ========================================");
     }
   
   // Set up timer to poll CSV file
   EventSetTimer(PollInterval);
   
   if(PollInterval < 1.0)
     {
      Print("  ✓ Timer started - monitoring CSV file every ", (int)(PollInterval * 1000), " ms (", DoubleToString(PollInterval, 3), " seconds)...");
     }
   else
     {
      Print("  ✓ Timer started - monitoring CSV file every ", DoubleToString(PollInterval, 1), " second(s)...");
     }
   Print("========================================");
   Print("  ✓ Ticket cache initialized (in-memory storage)");
   Print("  Cache will store master->slave ticket mappings");
   Print("  This avoids CSV file locking issues!");
   Print("========================================");
   
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   EventKillTimer();
   Print("CSV Monitor EA deinitialized.");
//---
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   // OnTick() not used - we use OnTimer() for polling
//---
  }
//+------------------------------------------------------------------+
//| Get normalized file path                                         |
//+------------------------------------------------------------------+
string GetNormalizedPath()
  {
   return NormalizePath(CSVPath);
  }
//+------------------------------------------------------------------+
//| Timer function - polls CSV file for new rows                     |
//+------------------------------------------------------------------+
void OnTimer()
  {
   timerCallCount++;
   
   // Debug: print every 10 timer calls to confirm it's working
   if(timerCallCount % 10 == 0)
     {
      Print("DEBUG: OnTimer() called ", timerCallCount, " times | File exists: ", (fileExists ? "Yes" : "No"));
      Print("  Cache size: ", ArraySize(ticketCache), " ticket mappings");
     }
   
   CheckForNewRows();
  }
//+------------------------------------------------------------------+
//| Check for new rows in CSV file                                   |
//+------------------------------------------------------------------+
void CheckForNewRows()
  {
   string filePath = GetNormalizedPath();
   
   // Check if file exists
   bool exists = CheckFileExists(filePath);
   if(!exists)
     {
      if(fileExists)
        {
         Print("⚠ CSV file was deleted or moved");
         fileExists = false;
         lastProcessedLineCount = 0;
         lastFileModTime = 0;
         lastFileSize = 0;
        }
      else if(timerCallCount % 20 == 0)  // Print debug every 20 calls if file not found
        {
         Print("========================================");
         Print("DEBUG: File not found!");
         Print("  Attempted path: ", filePath);
         Print("  MQL5 Files directory: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\");
         Print("  NOTE: MQL5 can only access files in its Files directory!");
         Print("  Expected full path: ", TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + filePath);
         Print("========================================");
        }
      return;  // File doesn't exist yet, wait
     }
   
   // File exists now (might be newly created)
   if(!fileExists)
     {
      fileExists = true;
      Print("✓ CSV file found - starting to monitor");
      GetFileStats(filePath);
      lastProcessedLineCount = CountCSVLines(filePath);
      Print("  Initial line count: ", lastProcessedLineCount);
      Print("  Initial file size: ", lastFileSize, " bytes");
      if(lastFileModTime > 0)
         Print("  Initial mod time: ", TimeToString(lastFileModTime, TIME_DATE|TIME_SECONDS));
      return;  // Don't process on first detection, just set baseline
     }
   
   // Get current file stats
   datetime currentModTime = 0;
   long currentFileSize = 0;
   GetFileStats(filePath, currentModTime, currentFileSize);
   
   // Debug output every 50 timer calls
   if(timerCallCount % 50 == 0)
     {
      Print("DEBUG: File check - ModTime: ", (currentModTime > 0 ? TimeToString(currentModTime, TIME_DATE|TIME_SECONDS) : "0"), 
            " | Size: ", currentFileSize, " | Lines: ", CountCSVLines(filePath));
     }
   
   // Check if file has been modified (more reliable than just counting lines)
   if(currentModTime <= lastFileModTime && currentFileSize <= lastFileSize)
     {
      return;  // No changes detected
     }
   
   // File has been modified!
   Print("========================================");
   Print(">>> FILE MODIFIED - CHECKING FOR NEW ROWS <<<");
   Print("  Previous mod time: ", (lastFileModTime > 0 ? TimeToString(lastFileModTime, TIME_DATE|TIME_SECONDS) : "0"));
   Print("  Current mod time: ", (currentModTime > 0 ? TimeToString(currentModTime, TIME_DATE|TIME_SECONDS) : "0"));
   Print("  Previous size: ", lastFileSize, " bytes");
   Print("  Current size: ", currentFileSize, " bytes");
   Print("========================================");
   
   // Count current lines in file
   int currentLineCount = CountCSVLines(filePath);
   Print("DEBUG: Current line count: ", currentLineCount, " | Last processed: ", lastProcessedLineCount);
   
   // Check if there are new lines
   if(currentLineCount > lastProcessedLineCount)
     {
      int newLinesCount = currentLineCount - lastProcessedLineCount;
      Print(">>> NEW ROWS DETECTED: ", newLinesCount, " row(s) <<<");
      
      // Read and print new rows
      ReadAndPrintNewRows(filePath, lastProcessedLineCount, newLinesCount);
      
      // Update last processed line count
      lastProcessedLineCount = currentLineCount;
     }
   else if(currentFileSize > lastFileSize)
     {
      Print("WARNING: File size increased (", lastFileSize, " -> ", currentFileSize, ") but line count didn't change (", currentLineCount, ").");
      Print("  This might indicate the file format changed or there's an issue reading the file.");
      Print("  DEBUG: Attempting to read file directly to diagnose...");
      
      // Try to read and print first few lines for debugging
      ResetLastError();
      int debugFile = FileOpen(filePath, FILE_READ|FILE_TXT|FILE_ANSI);
      if(debugFile != INVALID_HANDLE)
        {
         Print("  DEBUG: File opened successfully");
         // Read header
         string headerLine = FileReadString(debugFile);
         Print("  DEBUG: Header line: '", headerLine, "'");
         string headerFields[];
         ParseCSVLine(headerLine, headerFields);
         Print("  DEBUG: Header parsed into ", ArraySize(headerFields), " fields");
         for(int h = 0; h < ArraySize(headerFields) && h < 11; h++)
           {
            Print("    [", h, "] = '", headerFields[h], "'");
           }
         
         // Try to read first data row
         if(!FileIsEnding(debugFile))
           {
            string dataLine = FileReadString(debugFile);
            Print("  DEBUG: First data line: '", dataLine, "'");
            string dataFields[];
            ParseCSVLine(dataLine, dataFields);
            Print("  DEBUG: First data row parsed into ", ArraySize(dataFields), " fields");
            for(int d = 0; d < ArraySize(dataFields) && d < 11; d++)
              {
               Print("    [", d, "] = '", dataFields[d], "'");
              }
           }
         else
           {
            Print("  DEBUG: No data rows found after header");
           }
         
         FileClose(debugFile);
        }
      else
        {
         int error = GetLastError();
         Print("  DEBUG: Failed to open file for debugging. Error: ", error);
         ResetLastError();
        }
     }
   
   // Update tracking variables
   lastFileModTime = currentModTime;
   lastFileSize = currentFileSize;
  }
//+------------------------------------------------------------------+
//| Check if file exists                                             |
//+------------------------------------------------------------------+
bool CheckFileExists(string filePath)
  {
   ResetLastError();
   return FileIsExist(filePath);
  }
//+------------------------------------------------------------------+
//| Get file statistics (modification time and size)                 |
//+------------------------------------------------------------------+
void GetFileStats(string filePath)
  {
   datetime modTime = 0;
   long fileSize = 0;
   
   if(FileIsExist(filePath))
     {
      modTime = (datetime)FileGetInteger(filePath, FILE_MODIFY_DATE);
      fileSize = FileGetInteger(filePath, FILE_SIZE);
     }
   
   // Update global variables
   lastFileModTime = modTime;
   lastFileSize = fileSize;
  }
//+------------------------------------------------------------------+
//| Get file statistics with return values                           |
//+------------------------------------------------------------------+
void GetFileStats(string filePath, datetime &modTime, long &fileSize)
  {
   if(FileIsExist(filePath))
     {
      modTime = (datetime)FileGetInteger(filePath, FILE_MODIFY_DATE);
      fileSize = FileGetInteger(filePath, FILE_SIZE);
     }
   else
     {
      modTime = 0;
      fileSize = 0;
     }
  }
//+------------------------------------------------------------------+
//| Count total lines in CSV file (data rows only, excluding header) |
//+------------------------------------------------------------------+
int CountCSVLines(string filePath)
  {
   ResetLastError();
   // Read as text to properly handle line breaks
   int file = FileOpen(filePath, FILE_READ|FILE_TXT|FILE_ANSI);
   
   if(file == INVALID_HANDLE)
     {
      int error = GetLastError();
      if(error != 0 && timerCallCount % 50 == 0)  // Only print error every 50 calls to avoid spam
        {
         Print("ERROR: Failed to open CSV file for counting. Error: ", error);
         Print("  Path tried: ", filePath);
         ResetLastError();
        }
      return 0;
     }
   
   int lineCount = 0;
   bool isFirstLine = true;
   string line = "";
   
   while(!FileIsEnding(file))
     {
      line = FileReadString(file);
      if(line == "") break;
      
      // Skip header line (first line)
      if(isFirstLine)
        {
         isFirstLine = false;
         continue;
        }
      
      // Count non-empty data lines (trim whitespace first)
      string trimmed = line;
      StringTrimLeft(trimmed);
      StringTrimRight(trimmed);
      if(trimmed != "")
         lineCount++;
     }
   
   FileClose(file);
   return lineCount;
  }
//+------------------------------------------------------------------+
//| Parse CSV line into fields (split by comma)                      |
//+------------------------------------------------------------------+
void ParseCSVLine(string line, string &fields[])
  {
   ArrayResize(fields, 0);
   if(line == "") return;
   
   int startPos = 0;
   int len = StringLen(line);
   
   for(int i = 0; i <= len; i++)
     {
      if(i == len || StringGetCharacter(line, i) == ',')
        {
         string field = StringSubstr(line, startPos, i - startPos);
         // Remove quotes if present
         StringTrimLeft(field);
         StringTrimRight(field);
         int fieldLen = StringLen(field);
         if(fieldLen >= 2 && StringGetCharacter(field, 0) == '"' && StringGetCharacter(field, fieldLen - 1) == '"')
           {
            field = StringSubstr(field, 1, fieldLen - 2);
           }
         
         int size = ArraySize(fields);
         ArrayResize(fields, size + 1);
         fields[size] = field;
         startPos = i + 1;
        }
     }
  }
//+------------------------------------------------------------------+
//| Find best similar symbol from slave broker                        |
//+------------------------------------------------------------------+
string FindBestSimilarSymbol(string masterSymbol)
  {
   // Step 1: Try exact match first
   if(SymbolInfoInteger(masterSymbol, SYMBOL_SELECT))
     {
      return masterSymbol;
     }
   
   // Step 2: Get all symbols from slave broker (false = all symbols, not just market watch)
   int totalSymbols = SymbolsTotal(false);
   string bestMatch = "";
   int bestScore = 0;
   
   // Step 3: Try case-insensitive match
   for(int i = 0; i < totalSymbols; i++)
     {
      string symbolName = SymbolName(i, false);
      if(StringCompare(symbolName, masterSymbol, false) == 0)  // Case-insensitive
        {
         Print("Symbol matched (case-insensitive): '", masterSymbol, "' -> '", symbolName, "'");
         return symbolName;
        }
     }
   
   // Step 4: Find best similar symbol by comparing character similarity
   string masterUpper = masterSymbol;
   StringToUpper(masterUpper);
   
   for(int i = 0; i < totalSymbols; i++)
     {
      string symbolName = SymbolName(i, false);
      string symbolUpper = symbolName;
      StringToUpper(symbolUpper);
      
      // Calculate similarity score
      int score = 0;
      int minLen = MathMin(StringLen(masterUpper), StringLen(symbolUpper));
      
      // Check if master symbol is contained in slave symbol or vice versa
      if(StringFind(symbolUpper, masterUpper) >= 0 || StringFind(masterUpper, symbolUpper) >= 0)
        {
         score = minLen * 2;  // High score for substring match
        }
      else
        {
         // Count matching characters at same positions
         for(int j = 0; j < minLen; j++)
           {
            if(StringGetCharacter(masterUpper, j) == StringGetCharacter(symbolUpper, j))
               score++;
           }
        }
      
      // Prefer exact matches (after case-insensitive check)
      if(score > bestScore)
        {
         bestScore = score;
         bestMatch = symbolName;
        }
     }
   
   if(bestMatch != "" && bestScore > 0)
     {
      Print("Symbol matched (similarity): '", masterSymbol, "' -> '", bestMatch, "' (score: ", bestScore, ")");
      return bestMatch;
     }
   
   Print("ERROR: Could not find similar symbol for '", masterSymbol, "'");
   return "";
  }
//+------------------------------------------------------------------+
//| Get filling type for symbol                                       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingType(string symbol)
  {
   int filling = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   else
      return ORDER_FILLING_RETURN;
  }
//+------------------------------------------------------------------+
//| Execute open position trade                                       |
//+------------------------------------------------------------------+
ulong ExecuteOpenTrade(string symbol, string typeStr, double volume, double price, double sl, double tp, string comment)
  {
   Print("═══════════════════════════════════════════════════════════");
   Print(">>> EXECUTING OPEN TRADE <<<");
   Print("═══════════════════════════════════════════════════════════");
   
   // Validate symbol exists on slave broker
   if(!SymbolInfoInteger(symbol, SYMBOL_SELECT))
     {
      Print("ERROR: Symbol '", symbol, "' is not available on slave broker");
      return 0;
     }
   
   // Determine order type
   ENUM_ORDER_TYPE orderType;
   if(typeStr == "BUY" || typeStr == "0")
      orderType = ORDER_TYPE_BUY;
   else if(typeStr == "SELL" || typeStr == "1")
      orderType = ORDER_TYPE_SELL;
   else
     {
      Print("ERROR: Invalid type: ", typeStr);
      return 0;
     }
   
   // Get current market price
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double currentPrice = (orderType == ORDER_TYPE_BUY) ? ask : bid;
   
   // Normalize volume
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   
   if(volume < minLot) volume = minLot;
   if(volume > maxLot) volume = maxLot;
   volume = MathFloor(volume / lotStep) * lotStep;
   
   // Calculate SL and TP
   double finalSL = 0;
   double finalTP = 0;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   if(sl > 0)
     {
      finalSL = NormalizeDouble(sl, digits);
     }
   
   if(tp > 0)
     {
      finalTP = NormalizeDouble(tp, digits);
     }
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = volume;
   request.type = orderType;
   request.price = currentPrice;
   request.sl = finalSL;
   request.tp = finalTP;
   request.deviation = SlippagePoints;
   request.magic = SlaveMagicID;
   request.comment = comment;
   request.type_filling = GetFillingType(symbol);
   
   Print("TRADE REQUEST:");
   Print("  Symbol: ", request.symbol);
   Print("  Type: ", EnumToString(request.type));
   Print("  Volume: ", DoubleToString(request.volume, 2));
   Print("  Price: ", DoubleToString(request.price, digits));
   Print("  SL: ", (request.sl > 0 ? DoubleToString(request.sl, digits) : "Not set"));
   Print("  TP: ", (request.tp > 0 ? DoubleToString(request.tp, digits) : "Not set"));
   Print("  Magic: ", request.magic);
   
   // Execute trade
   ResetLastError();
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE)
     {
      Print("═══════════════════════════════════════════════════════════");
      Print("✓✓✓ TRADE OPENED SUCCESSFULLY! ✓✓✓");
      Print("  Slave Ticket: ", result.order);
      Print("  Deal: ", result.deal);
      Print("  Volume: ", DoubleToString(result.volume, 2));
      Print("  Price: ", DoubleToString(result.price, digits));
      Print("═══════════════════════════════════════════════════════════");
      return result.order;  // Return slave ticket
     }
   else
     {
      Print("═══════════════════════════════════════════════════════════");
      Print("✗✗✗ TRADE OPEN FAILED! ✗✗✗");
      Print("  Error code: ", result.retcode);
      Print("  Error description: ", result.comment);
      Print("  Request ID: ", result.request_id);
      Print("═══════════════════════════════════════════════════════════");
      return 0;
     }
  }
//+------------------------------------------------------------------+
//| Close position by slave ticket                                    |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong slaveTicket)
  {
   Print("═══════════════════════════════════════════════════════════");
   Print(">>> CLOSING POSITION <<<");
   Print("  Slave Ticket: ", slaveTicket);
   Print("═══════════════════════════════════════════════════════════");
   
   // Check if position exists
   if(!PositionSelectByTicket(slaveTicket))
     {
      Print("WARNING: Position ", slaveTicket, " does not exist (may have been closed already)");
      return false;
     }
   
   // Get position details
   string posSymbol = PositionGetString(POSITION_SYMBOL);
   double posVolume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   
   // Determine close order type (opposite of position type)
   ENUM_ORDER_TYPE closeType;
   if(posType == POSITION_TYPE_BUY)
      closeType = ORDER_TYPE_SELL;
   else
      closeType = ORDER_TYPE_BUY;
   
   // Get current market price
   double ask = SymbolInfoDouble(posSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(posSymbol, SYMBOL_BID);
   double closePrice = (closeType == ORDER_TYPE_SELL) ? bid : ask;
   
   // Prepare trade request
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.position = slaveTicket;
   request.symbol = posSymbol;
   request.volume = posVolume;
   request.type = closeType;
   request.price = closePrice;
   request.deviation = SlippagePoints;
   request.magic = SlaveMagicID;
   request.comment = "Slave_Close";
   request.type_filling = GetFillingType(posSymbol);
   
   int digits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
   Print("CLOSE REQUEST:");
   Print("  Position Ticket: ", slaveTicket);
   Print("  Symbol: ", request.symbol);
   Print("  Type: ", EnumToString(request.type));
   Print("  Volume: ", DoubleToString(request.volume, 2));
   Print("  Price: ", DoubleToString(request.price, digits));
   
   // Execute trade
   ResetLastError();
   bool success = OrderSend(request, result);
   
   if(success && result.retcode == TRADE_RETCODE_DONE)
     {
      Print("═══════════════════════════════════════════════════════════");
      Print("✓✓✓ POSITION CLOSED SUCCESSFULLY! ✓✓✓");
      Print("  Deal: ", result.deal);
      Print("  Volume: ", DoubleToString(result.volume, 2));
      Print("  Price: ", DoubleToString(result.price, digits));
      Print("═══════════════════════════════════════════════════════════");
      return true;
     }
   else
     {
      Print("═══════════════════════════════════════════════════════════");
      Print("✗✗✗ POSITION CLOSE FAILED! ✗✗✗");
      Print("  Error code: ", result.retcode);
      Print("  Error description: ", result.comment);
      Print("═══════════════════════════════════════════════════════════");
      return false;
     }
  }
//+------------------------------------------------------------------+
//| Update CSV file with slave ticket for a specific row              |
//| FIXED: Added retry logic for file locking issues (Error 5004)     |
//+------------------------------------------------------------------+
void UpdateCSVWithSlaveTicket(string filePath, int rowIndex, ulong slaveTicket)
  {
   Print(">>> Updating CSV with slave ticket: ", slaveTicket, " for row #", (rowIndex + 1), " <<<");
   
   // Read entire file into memory (with retry for file locking)
   string lines[];
   int maxRetries = 5;
   int retryDelay = 100;  // milliseconds
   int file = INVALID_HANDLE;
   
   // Retry opening file for reading
   for(int retry = 0; retry < maxRetries; retry++)
     {
      ResetLastError();
      file = FileOpen(filePath, FILE_READ|FILE_TXT|FILE_ANSI);
      
      if(file != INVALID_HANDLE)
         break;  // Success!
      
      int error = GetLastError();
      if(retry < maxRetries - 1)
        {
         Print("WARNING: Failed to open CSV for reading (attempt ", (retry + 1), "/", maxRetries, "). Error: ", error);
         Print("  Retrying in ", retryDelay, "ms...");
         Sleep(retryDelay);
         retryDelay += 50;  // Increase delay for each retry
        }
      else
        {
         Print("ERROR: Failed to open CSV file for reading after ", maxRetries, " attempts. Error: ", error);
         Print("  File path: ", filePath);
         Print("  This usually means the file is locked by another process (Python script).");
         ResetLastError();
         return;
        }
     }
   
   // Read all lines
   int lineCount = 0;
   while(!FileIsEnding(file))
     {
      string line = FileReadString(file);
      // Remove trailing newline/carriage return if present
      StringTrimRight(line);
      if(line == "") break;
      
      int size = ArraySize(lines);
      ArrayResize(lines, size + 1);
      lines[size] = line;
      lineCount++;
     }
   FileClose(file);
   
   // Check if row index is valid (rowIndex is 0-based for data rows, but we have header at index 0)
   // So rowIndex 0 = first data row (after header)
   if(rowIndex < 0 || rowIndex >= lineCount - 1)  // -1 because header doesn't count
     {
      Print("ERROR: Invalid row index: ", rowIndex, " (file has ", (lineCount - 1), " data rows)");
      return;
     }
   
   // Parse the target line (rowIndex + 1 because header is at index 0)
   int targetLineIndex = rowIndex + 1;
   string fields[];
   ParseCSVLine(lines[targetLineIndex], fields);
   
   // Ensure we have at least 11 fields (add empty fields if needed)
   while(ArraySize(fields) < 11)
     {
      int size = ArraySize(fields);
      ArrayResize(fields, size + 1);
      fields[size] = "";
     }
   
   // Update field 10 (slave ticket, 0-based index)
   fields[10] = IntegerToString(slaveTicket);
   
   // Reconstruct the line
   string newLine = "";
   for(int i = 0; i < ArraySize(fields); i++)
     {
      if(i > 0) newLine += ",";
      // Add quotes if field contains comma or spaces
      string field = fields[i];
      if(StringFind(field, ",") >= 0 || StringFind(field, " ") >= 0)
        {
         newLine += "\"" + field + "\"";
        }
      else
        {
         newLine += field;
        }
     }
   
   // Update the line in array
   lines[targetLineIndex] = newLine;
   
   // Write all lines back to file (with retry for file locking)
   retryDelay = 100;  // Reset delay
   file = INVALID_HANDLE;
   
   for(int retry = 0; retry < maxRetries; retry++)
     {
      ResetLastError();
      file = FileOpen(filePath, FILE_WRITE|FILE_TXT|FILE_ANSI);
      
      if(file != INVALID_HANDLE)
         break;  // Success!
      
      int error = GetLastError();
      if(retry < maxRetries - 1)
        {
         Print("WARNING: Failed to open CSV for writing (attempt ", (retry + 1), "/", maxRetries, "). Error: ", error);
         Print("  Error 5004 = File is locked by another process (Python script writing to file)");
         Print("  Retrying in ", retryDelay, "ms...");
         Sleep(retryDelay);
         retryDelay += 50;  // Increase delay for each retry
        }
      else
        {
         Print("ERROR: Failed to open CSV file for writing after ", maxRetries, " attempts. Error: ", error);
         Print("  File path: ", filePath);
         Print("  This usually means the file is locked by another process (Python script).");
         Print("  The slave ticket was NOT saved to CSV file!");
         ResetLastError();
         return;
        }
     }
   
   // Write all lines
   for(int i = 0; i < ArraySize(lines); i++)
     {
      FileWriteString(file, lines[i] + "\n");
     }
   
   FileFlush(file);
   FileClose(file);
   
   Print("✓✓✓ Successfully updated CSV row #", (rowIndex + 1), " with slave ticket: ", slaveTicket, " ✓✓✓");
  }
//+------------------------------------------------------------------+
//| Store master ticket -> slave ticket mapping in cache              |
//+------------------------------------------------------------------+
void StoreTicketMapping(ulong masterTicket, ulong slaveTicket, string symbol)
  {
   // Check if mapping already exists
   int index = FindTicketMappingIndex(masterTicket);
   
   if(index >= 0)
     {
      // Update existing mapping
      ticketCache[index].slaveTicket = slaveTicket;
      ticketCache[index].symbol = symbol;
      ticketCache[index].openTime = TimeCurrent();
      Print("  Updated existing cache entry for master ticket: ", masterTicket);
     }
   else
     {
      // Add new mapping
      int size = ArraySize(ticketCache);
      ArrayResize(ticketCache, size + 1);
      ticketCache[size].masterTicket = masterTicket;
      ticketCache[size].slaveTicket = slaveTicket;
      ticketCache[size].symbol = symbol;
      ticketCache[size].openTime = TimeCurrent();
      Print("  Added new cache entry: Master ", masterTicket, " -> Slave ", slaveTicket);
     }
  }
//+------------------------------------------------------------------+
//| Get slave ticket from cache by master ticket                      |
//+------------------------------------------------------------------+
ulong GetSlaveTicketFromCache(ulong masterTicket)
  {
   int index = FindTicketMappingIndex(masterTicket);
   if(index >= 0)
     {
      return ticketCache[index].slaveTicket;
     }
   return 0;  // Not found
  }
//+------------------------------------------------------------------+
//| Find index of ticket mapping in cache                             |
//+------------------------------------------------------------------+
int FindTicketMappingIndex(ulong masterTicket)
  {
   for(int i = 0; i < ArraySize(ticketCache); i++)
     {
      if(ticketCache[i].masterTicket == masterTicket)
         return i;
     }
   return -1;  // Not found
  }
//+------------------------------------------------------------------+
//| Remove ticket mapping from cache                                  |
//+------------------------------------------------------------------+
void RemoveTicketMapping(ulong masterTicket)
  {
   int index = FindTicketMappingIndex(masterTicket);
   if(index >= 0)
     {
      int size = ArraySize(ticketCache);
      
      // Move last element to this position
      if(index < size - 1)
        {
         ticketCache[index] = ticketCache[size - 1];
        }
      
      // Resize array to remove last element
      ArrayResize(ticketCache, size - 1);
      Print("  Removed cache entry for master ticket: ", masterTicket);
     }
  }
//+------------------------------------------------------------------+
//| Read and print new rows from CSV file                            |
//+------------------------------------------------------------------+
void ReadAndPrintNewRows(string filePath, int skipLines, int newLinesCount)
  {
   Print("═══════════════════════════════════════════════════════════");
   Print(">>> ReadAndPrintNewRows CALLED <<<");
   Print("  File path: ", filePath);
   Print("  Skip lines: ", skipLines);
   Print("  New lines count: ", newLinesCount);
   Print("═══════════════════════════════════════════════════════════");
   
   ResetLastError();
   // Read as text to properly handle CSV parsing
   int file = FileOpen(filePath, FILE_READ|FILE_TXT|FILE_ANSI);
   
   if(file == INVALID_HANDLE)
     {
      int error = GetLastError();
      Print("ERROR: Failed to open CSV file for reading. Error: ", error);
      Print("  Path tried: ", filePath);
      ResetLastError();
      return;
     }
   
   Print("✓ File opened successfully");
   
   // Skip header line (first line)
   string headerLine = FileReadString(file);
   Print("  Header line: ", headerLine);
   
   // Skip already processed lines
   for(int i = 0; i < skipLines; i++)
     {
      if(FileIsEnding(file)) break;
      FileReadString(file);  // Skip this line
     }
   
   // Read and print new rows
   for(int i = 0; i < newLinesCount; i++)
     {
      if(FileIsEnding(file)) break;
      
      string line = FileReadString(file);
      if(line == "") break;
      
      // Parse CSV line into fields
      string fields[];
      ParseCSVLine(line, fields);
      
      // Validate we have at least some fields
      if(ArraySize(fields) == 0) continue;
      
      // Extract fields (handle cases where we might have fewer than 11 fields)
      string timeStr = (ArraySize(fields) > 0) ? fields[0] : "";
      string ticketStr = (ArraySize(fields) > 1) ? fields[1] : "";
      string symbol = (ArraySize(fields) > 2) ? fields[2] : "";
      string typeStr = (ArraySize(fields) > 3) ? fields[3] : "";
      string actionStr = (ArraySize(fields) > 4) ? fields[4] : "";
      string volumeStr = (ArraySize(fields) > 5) ? fields[5] : "";
      string priceStr = (ArraySize(fields) > 6) ? fields[6] : "";
      string slStr = (ArraySize(fields) > 7) ? fields[7] : "";
      string tpStr = (ArraySize(fields) > 8) ? fields[8] : "";
      string comment = (ArraySize(fields) > 9) ? fields[9] : "";
      string slaveTicketStr = (ArraySize(fields) > 10) ? fields[10] : "";
      
      // Validate data
      if(timeStr == "" && ticketStr == "" && symbol == "")
        {
         continue;  // Skip empty rows
        }
      
      // Print the new row data - EXACTLY like working version
      Print("--- NEW ROW #", (skipLines + i + 1), " ---");
      Print("  Time: ", (timeStr != "" ? timeStr : "N/A"));
      Print("  Ticket: ", (ticketStr != "" ? ticketStr : "N/A"));
      Print("  Symbol: ", (symbol != "" ? symbol : "N/A"));
      Print("  Type: ", (typeStr != "" ? typeStr : "N/A"));
      Print("  Action: ", (actionStr != "" ? actionStr : "N/A"));
      Print("  Volume: ", (volumeStr != "" ? volumeStr : "N/A"), " lots");
      Print("  Price: ", (priceStr != "" ? priceStr : "N/A"));
      Print("  Stop Loss: ", (slStr != "" ? slStr : "Not set"));
      Print("  Take Profit: ", (tpStr != "" ? tpStr : "Not set"));
      Print("  Comment: ", (comment != "" ? comment : "No comment"));
      Print("  Slave Ticket: ", (slaveTicketStr != "" ? slaveTicketStr : "Not set"));
      Print("---");
      
      // Normalize action string to uppercase for comparison
      string actionUpper = actionStr;
      StringToUpper(actionUpper);
      StringTrimLeft(actionUpper);
      StringTrimRight(actionUpper);
      
      // Execute trade based on action
      if(actionUpper == "OPEN")
        {
         // Open position logic
         Print(">>> PROCESSING OPEN POSITION <<<");
         
         // Find best similar symbol on slave broker
         string slaveSymbol = FindBestSimilarSymbol(symbol);
         if(slaveSymbol == "")
           {
            Print("ERROR: Could not find matching symbol for '", symbol, "' on slave broker");
            Print("  Skipping this trade...");
            continue;
           }
         
         // Parse trade parameters
         double volume = StringToDouble(volumeStr);
         double price = StringToDouble(priceStr);
         double sl = StringToDouble(slStr);
         double tp = StringToDouble(tpStr);
         
         // Execute open trade
         ulong slaveTicket = ExecuteOpenTrade(slaveSymbol, typeStr, volume, price, sl, tp, comment);
         
         if(slaveTicket > 0)
           {
            // Parse master ticket
            ulong masterTicket = (ulong)StringToInteger(ticketStr);
            
            // Store in cache (memory) - this avoids CSV file locking issues!
            StoreTicketMapping(masterTicket, slaveTicket, symbol);
            
            // Try to update CSV file (but don't fail if it's locked - we have cache!)
            UpdateCSVWithSlaveTicket(filePath, skipLines + i, slaveTicket);
            
            Print("✓ Trade executed - Master ticket: ", masterTicket, " -> Slave ticket: ", slaveTicket);
            Print("  Mapping stored in cache (", ArraySize(ticketCache), " total mappings)");
           }
         else
           {
            Print("✗ Failed to execute open trade");
           }
        }
      else if(actionUpper == "CLOSE")
        {
         // Close position logic
         Print(">>> PROCESSING CLOSE POSITION <<<");
         
         // Parse master ticket
         ulong masterTicket = (ulong)StringToInteger(ticketStr);
         ulong slaveTicket = 0;
         
         // First, try to get slave ticket from CSV (if available)
         if(slaveTicketStr != "" && slaveTicketStr != "Not set" && slaveTicketStr != "0")
           {
            slaveTicket = (ulong)StringToInteger(slaveTicketStr);
            Print("  Found slave ticket in CSV: ", slaveTicket);
           }
         
         // If not in CSV, try to get from cache (memory)
         if(slaveTicket == 0)
           {
            slaveTicket = GetSlaveTicketFromCache(masterTicket);
            if(slaveTicket > 0)
              {
               Print("  Found slave ticket in cache: ", slaveTicket);
              }
           }
         
         // If still not found, skip
         if(slaveTicket == 0)
           {
            Print("WARNING: No slave ticket found for close action!");
            Print("  Master ticket: ", masterTicket);
            Print("  Cache size: ", ArraySize(ticketCache), " mappings");
            Print("  Skipping close order...");
            continue;
           }
         
         // Check if position exists
         if(!PositionSelectByTicket(slaveTicket))
           {
            Print("WARNING: Position with ticket ", slaveTicket, " does not exist");
            Print("  It may have been closed already or never opened");
            Print("  Removing from cache...");
            RemoveTicketMapping(masterTicket);
            continue;
           }
         
         // Close the position
         bool closed = ClosePositionByTicket(slaveTicket);
         
         if(closed)
           {
            Print("✓ Position closed successfully");
            // Remove from cache after successful close
            RemoveTicketMapping(masterTicket);
           }
         else
           {
            Print("✗ Failed to close position");
           }
        }
      else
        {
         Print("WARNING: Unknown action '", actionUpper, "' (original: '", actionStr, "'). Expected 'OPEN' or 'CLOSE'");
        }
     }
   
   FileClose(file);
  }
//+------------------------------------------------------------------+

