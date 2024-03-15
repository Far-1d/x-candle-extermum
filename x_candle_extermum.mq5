//+------------------------------------------------------------------+
//|                                            x_candle_extermum.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://github.com/Far-1d"
#property version   "1.00"

//--- import library
#include <trade/trade.mqh>
CTrade trade;


//---inputs
input group "Strategy Config";
input int X                = 15;                   // number of candles to lookback (x)

input group "Position Config";
input int Magic            = 4444;
enum lot_method {
   for_x_dollar_balance,
   constant
};
input lot_method lot_type  = constant;              // how to calculate lot size? 
input int dollar_balance   = 100;                   // base account dollar for balance and equity calculation
input double lot_value     = 0.1;                   // lot size
input int sl_distance      = 10;                    // sl distance in pip
//input int max_lot          = 20;                    // maximum lot size of each trade
enum tp_method {
   TP1,
   TP2,
   Trail,
   TP1_TP2,
   TP1_Trail,
   TP2_Trail,
   TP1_TP2_Trail
};
input tp_method tp_type = TP1_TP2_Trail;            // which tp to be active?(below inputs will be ignored based on active tp4)

input int tp1_distance     = 20;                    // tp 1 distance in pip
input int tp2_distance     = 30;                    // tp 2 and trail distance in pip
input int tp1_percent      = 50;                    // % percent of position to close at tp 1 
input int tp2_percent      = 30;                    // % percent of position to close at tp 2 
input int trail_percent    = 20;                    // % percent of position to close at trail 
input int trail_pip        = 30;                    // trail distance in pips when tp 2 reached

input group "Risk free Config";
input bool use_rf          = false;                 // Enable Risk Free ?
input double rf_distance   = 5;                     // Price distance from entry (pip)

//--- global variables
double lot_size;                       // calculated initial lot size based on inputs

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){

   trade.SetExpertMagicNumber(Magic);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){

   
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){

   //--- check new candle
   int static totalbars = iBars(_Symbol, PERIOD_CURRENT);
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   
   if (totalbars != bars)
   {
      //--- check bars for setup
      check_bars();
      
      totalbars = bars;
   }
   
      
   //--- trail and risk free part 
   if (PositionsTotal()>0){
      for (int i=0; i<PositionsTotal(); i++){
         ulong tikt = PositionGetTicket(i);
         if (PositionSelectByTicket(tikt)){
            //--- checking for risk free opportunity
            riskfree(tikt);
            
            if (PositionGetInteger(POSITION_MAGIC) == Magic && PositionGetString(POSITION_COMMENT) == "trail"){
               string type;
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) type = "BUY";
               else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) type = "SELL";
               trailing(tikt, type);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| check last X candles for a setup                                 |
//+------------------------------------------------------------------+
void check_bars(){
   
   double
      highest_high   = 0,
      lowest_low     = 10000000000000000;
   
   for (int i=2;  i<=X+1;  i++)
   {
      double 
         high = iHigh(_Symbol, PERIOD_CURRENT, i),
         low  = iLow(_Symbol, PERIOD_CURRENT, i);
   
      if (high > highest_high) highest_high = high;
      if (low < lowest_low) lowest_low = low;
   }
   
   //--- calculate lot size
   if (lot_type == 1) lot_size = lot_value;
   else lot_size = lot_value*(AccountInfoDouble(ACCOUNT_BALANCE)/dollar_balance);
   
   //--- get last close price
   double last_close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if (last_close > highest_high)   open_position("BUY"); 
   if (last_close < lowest_low)     open_position("SELL");
}


//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Open positions with requote resistant method                     |
//+------------------------------------------------------------------+
void open_position(string type){

   if (type == "BUY"){
      double 
         ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
         sl  = ask - (sl_distance*10*_Point),
         tp1 = ask + (tp1_distance*10*_Point),
         tp2 = ask + (tp2_distance*10*_Point),
         lt1 = NormalizeDouble(lot_size*tp1_percent/100, 2),
         lt2 = NormalizeDouble(lot_size*tp2_percent/100, 2),
         lt3 = NormalizeDouble(lot_size*trail_percent/100, 2);
         Print("ask = ", ask, "   sl = ", sl, "   tp1 = ", tp1, "   tp2 = ", tp2, "    lt1 = ", lt1);
      
      if (tp_type == 0){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               Print("Only tp1 Buy Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      } else if (tp_type == 1){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               Print("Only tp2 Buy Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 2){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("Only trailing Buy Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 3){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               Print("tp1 and tp2 Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      
      } else if (tp_type == 4){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("tp1 and trail Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      
      } else if (tp_type == 5){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("tp2 and trail Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
           
      } else if (tp_type == 6){
         int counting = 0;
         while(true){
            if (place_order("BUY", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("BUY", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("BUY", lt3, sl, 0, "trail")){
               Print("All Buy Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
      }
      
   } else {
      double 
         bid = SymbolInfoDouble(_Symbol, SYMBOL_BID),
         sl  = bid + (sl_distance*10*_Point),
         tp1 = bid - (tp1_distance*10*_Point),
         tp2 = bid - (tp2_distance*10*_Point),
         lt1 = NormalizeDouble(lot_size*tp1_percent/100, 2),
         lt2 = NormalizeDouble(lot_size*tp2_percent/100, 2),
         lt3 = NormalizeDouble(lot_size*trail_percent/100, 2);
         Print("bid = ", bid, "   sl = ", sl, "   tp1 = ", tp1, "   tp2 = ", tp2, "    lt1 = ", lt1);
      if (tp_type == 0){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               Print("Only tp1 Sell Order Entered @bid");
               break;
            } else counting ++;

            if (counting >= 10) break;
         }
         
      } else if (tp_type == 1){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               Print("Only tp2 Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 2){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("Only trailing Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 3){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               Print("tp1 and tp2 Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 4){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("tp1 and trail Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 5){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("tp2 and trail Sell Order Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
      } else if (tp_type == 6){
         int counting = 0;
         while(true){
            if (place_order("SELL", lt1, sl, tp1)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt2, sl, tp2)){
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }
         
         while(true){
            if (place_order("SELL", lt3, sl, 0, "trail")){
               Print("All Sell Orders Entered");
               break;
            } else counting ++;
            
            if (counting >= 10) break;
         }

      }
   }
}


//+------------------------------------------------------------------+
//| Place orders from values returned from open_position()           |
//+------------------------------------------------------------------+
bool place_order(string type, double lots, double sl, double tp, string comment=""){
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK); 
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   Print("placing orders");
   
   if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) && lots>0){
      lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   }
   
   int parts = 1;

   if (type == "BUY"){
      if (trade.Buy(lots, _Symbol, 0, sl, tp, comment))
      {
         int tot = PositionsTotal();
         return true;
      }
      
   } else {
      if (trade.Sell(lots, _Symbol, 0, sl, tp, comment))
      {
         int tot = PositionsTotal();
         return true;
      }
      
   }
   return false;
}


//+------------------------------------------------------------------+
//| trailing function                                                |
//+------------------------------------------------------------------+
void trailing(ulong tikt , string type){
   PositionSelectByTicket(tikt);
   double entry         = PositionGetDouble(POSITION_PRICE_OPEN);
   double curr_sl       = PositionGetDouble(POSITION_SL);
   double curr_tp       = PositionGetDouble(POSITION_TP); 
   double ask           = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid           = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(type == "BUY"){
      if (ask > PositionGetDouble(POSITION_PRICE_OPEN)+(tp2_distance*10*_Point)){
         if (ask-curr_sl > trail_pip*10*_Point){
            trade.PositionModify(tikt, ask - trail_pip*10*_Point, curr_tp);
            Print("changed buy trailed to ", ask - trail_pip*10*_Point);
         }
      }
   } else {
      if (bid < PositionGetDouble(POSITION_PRICE_OPEN)-(tp2_distance*10*_Point)){
         if (curr_sl-bid > trail_pip*10*_Point){
            trade.PositionModify(tikt, bid + trail_pip*10*_Point, curr_tp);
            Print("changed sell trailed to ", bid + trail_pip*10*_Point);
         }
      }
   }
   
}

//+----------------------------------------------------------------------+
//| this function riskfrees positions no matter if trailing is active  |
//+----------------------------------------------------------------------+
void riskfree(ulong tikt){
   if (use_rf) {
      //PositionSelectByTicket(tikt)
      double
         entry = PositionGetDouble(POSITION_PRICE_OPEN),
         tp = PositionGetDouble(POSITION_TP),
         sl = PositionGetDouble(POSITION_SL),
         ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK),
         bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      
      double comission_price = calculate_comission_for_riskfree(tikt);
     
      if (pos_type == POSITION_TYPE_BUY){
         if (ask - entry >= rf_distance*10*_Point && sl < entry){
            trade.PositionModify(tikt, entry+comission_price, tp);
            Print("buy position riskfreed to ", entry);
         }
      }
      
      if (pos_type == POSITION_TYPE_SELL){
         if (entry - bid >= rf_distance*10*_Point && sl > entry){
            trade.PositionModify(tikt, entry-comission_price, tp);
            Print("sell position riskfreed to ", entry);
         }
      }
   }
}


//--- calculate the price change needed to make for the comission fee , riskfree must have zero loss
double calculate_comission_for_riskfree(ulong tikt){
   HistoryDealSelect(tikt);
   double comission  = HistoryDealGetDouble(tikt, DEAL_COMMISSION);
   double volume     = HistoryDealGetDouble(tikt, DEAL_VOLUME);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double points = MathAbs((2*comission)/(volume*tick_value));
   
   return NormalizeDouble(points*_Point, _Digits);
}