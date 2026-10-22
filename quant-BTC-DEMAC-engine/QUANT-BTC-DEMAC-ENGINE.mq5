
#property strict
#property version "1.00"
#property description "BTCUSD Daily 10/20 EMA Crossover EA"

#include <Trade/Trade.mqh>

input string InpSymbol          = "";       // Blank = chart symbol
input double InpLots            = 0.01;     // Fixed trade volume
input int    InpFastEMA         = 10;
input int    InpSlowEMA         = 20;
input ulong  InpMagic           = 10202026;
input int    InpDeviationPoints = 100;

CTrade trade;

int fastHandle = INVALID_HANDLE;
int slowHandle = INVALID_HANDLE;

datetime lastDailyBar = 0;
int pendingDirection = 0; // 1 = Buy, -1 = Sell
bool closuresComplete = false;
bool blockedByForeignPosition = false;

string TradeSymbol()
{
   if(InpSymbol == "")
      return _Symbol;

   return InpSymbol;
}

bool IsOurPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   return
      PositionGetString(POSITION_SYMBOL) == TradeSymbol()
      && (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic;
}

bool HasOurPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket != 0 && IsOurPosition(ticket))
         return true;
   }

   return false;
}

// On a netting account, manual and EA trades on one symbol
// cannot be safely isolated as independent positions.
bool HasForeignNettingPosition()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)
      == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != TradeSymbol())
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         return true;
   }

   return false;
}

bool ReadCrossover(int &direction)
{
   direction = 0;

   double fast[2];
   double slow[2];

   // Read only completed daily candles.
   // Index 0 = shift 2; index 1 = shift 1.
   if(CopyBuffer(fastHandle, 0, 1, 2, fast) != 2)
      return false;

   if(CopyBuffer(slowHandle, 0, 1, 2, slow) != 2)
      return false;

   // Bullish: fast EMA crossed from at/below to above.
   if(fast[0] <= slow[0] && fast[1] > slow[1])
      direction = 1;

   // Bearish: fast EMA crossed from at/above to below.
   if(fast[0] >= slow[0] && fast[1] < slow[1])
      direction = -1;

   return true;
}

bool CloseOurPositions()
{
   bool requestsOK = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 || !IsOurPosition(ticket))
         continue;

      ResetLastError();

      bool sent = trade.PositionClose(ticket);
      uint rc = trade.ResultRetcode();

      Print("Close ticket ", ticket,
            "; request=", sent,
            "; result=", rc,
            " ", trade.ResultRetcodeDescription());

      if(!sent ||
         (rc != TRADE_RETCODE_DONE &&
          rc != TRADE_RETCODE_DONE_PARTIAL))
      {
         requestsOK = false;
      }
   }

   // Verify the account state independently.
   if(HasOurPositions())
      return false;

   return requestsOK;
}

bool OpenSignalPosition()
{
   bool sent = false;

   if(pendingDirection == 1)
   {
      sent = trade.Buy(
         InpLots, TradeSymbol(), 0, 0, 0,
         "BTC EMA 10/20 Buy"
      );
   }
   else if(pendingDirection == -1)
   {
      sent = trade.Sell(
         InpLots, TradeSymbol(), 0, 0, 0,
         "BTC EMA 10/20 Sell"
      );
   }
   else
   {
      return false;
   }

   uint rc = trade.ResultRetcode();

   Print("Open request=", sent,
         "; result=", rc,
         " ", trade.ResultRetcodeDescription());

   if(sent &&
      (rc == TRADE_RETCODE_DONE ||
       rc == TRADE_RETCODE_DONE_PARTIAL ||
       rc == TRADE_RETCODE_PLACED))
   {
      pendingDirection = 0;
      closuresComplete = false;
      return true;
   }

   // Keep the signal pending so a failed request can be retried.
   // Before retrying, check whether the prior request actually
   // created a position, to reduce duplicate-order risk.
   return false;
}

void ProcessPendingSignal()
{
   if(pendingDirection == 0)
      return;

   if(HasForeignNettingPosition())
   {
      if(!blockedByForeignPosition)
         Print("Trading paused: foreign BTC position on netting account.");

      blockedByForeignPosition = true;
      return;
   }

   blockedByForeignPosition = false;

   // First close our old positions, and verify they are gone.
   if(!closuresComplete)
   {
      CloseOurPositions();

      if(HasOurPositions())
         return;

      closuresComplete = true;
   }

   // If a previous opening request succeeded but its response
   // was uncertain, do not send another order if our position exists.
   if(HasOurPositions())
   {
      pendingDirection = 0;
      closuresComplete = false;
      Print("Existing EA position detected; duplicate entry prevented.");
      return;
   }

   OpenSignalPosition();
}

int OnInit()
{
   if(InpFastEMA < 1 || InpSlowEMA < 1 ||
      InpFastEMA >= InpSlowEMA || InpLots <= 0)
   {
      Print("Invalid inputs. Fast EMA must be smaller than slow EMA.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!SymbolSelect(TradeSymbol(), true))
   {
      Print("Cannot select symbol: ", TradeSymbol());
      return INIT_FAILED;
   }

   fastHandle = iMA(
      TradeSymbol(), PERIOD_D1, InpFastEMA,
      0, MODE_EMA, PRICE_CLOSE
   );

   slowHandle = iMA(
      TradeSymbol(), PERIOD_D1, InpSlowEMA,
      0, MODE_EMA, PRICE_CLOSE
   );

   if(fastHandle == INVALID_HANDLE ||
      slowHandle == INVALID_HANDLE)
   {
      Print("Failed to initialize EMA indicators.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(TradeSymbol());
   trade.SetAsyncMode(false);

   // Avoid entering a historical signal immediately on attachment.
   lastDailyBar = iTime(TradeSymbol(), PERIOD_D1, 0);

   Print("BTC EMA EA initialized on ", TradeSymbol(),
         ". Attach to a demo account first.");

   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime currentBar = iTime(TradeSymbol(), PERIOD_D1, 0);

   if(currentBar == 0)
      return;

   // Detect a new daily bar, meaning the previous daily candle closed.
   if(currentBar != lastDailyBar)
   {
      lastDailyBar = currentBar;

      // Do not replace a signal that is still being processed.
      if(pendingDirection == 0)
      {
         int signal = 0;

         if(ReadCrossover(signal) && signal != 0)
         {
            pendingDirection = signal;
            closuresComplete = false;

            Print("Daily crossover detected: ",
                  signal == 1 ? "BUY" : "SELL");
         }
      }
   }

   // Retry pending operations on subsequent ticks if necessary.
   ProcessPendingSignal();
}

void OnDeinit(const int reason)
{
   if(fastHandle != INVALID_HANDLE)
      IndicatorRelease(fastHandle);

   if(slowHandle != INVALID_HANDLE)
      IndicatorRelease(slowHandle);
}
