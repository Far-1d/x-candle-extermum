//+------------------------------------------------------------------+
//|                                            x_candle_extermum.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                        https://github.com/Far-1d |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://github.com/Far-1d"
#property version   "1.60"
#property description "Date Modified: 2024-04-28"
#property description "First BackTest"

//--- import library
#include <trade/trade.mqh>
CTrade trade;

//--- enums
enum lot_methods {
   for_x_dollar_balance,
   constant
};

enum box_heights {
   high_low,            // Shadow (High to Low)
   open_close           // Body (Open to Close)
};
enum tp_method {
   TP1,
   TP2,
   Trail,
   TP1_TP2,
   TP1_Trail,
   TP2_Trail,
   TP1_TP2_Trail
};

//---inputs
input group "Strategy Config";
input int breakout_candles = 1;                    // Number of Candles for Breaking the Box
//input box_heights bcm      = high_low;             // Breakout Candle Calculation Method
input int box_percent      = 100;                  // Percent of Box Height to be Breaked by Candle
//input int entry_distance   = 5;                    // Entry Distance(not active)

input group "Box Config";
input int X                      = 15;             // Box Candles (x)
input box_heights height_method  = high_low;       // how to calculate box height ?
input int max_box_height         = 100;            // Max Box Height
input int min_box_height         = 20;             // Min Box Height

input group "Filter Config";
input int rest             = 50;                   // Minimum Candles to Rest Between Positions
input int max_spread       = 20;                   // Max Spread in Point
input string trade_time_s  = "00:00";              // Trade Start Time
input string trade_time_e  = "20:00";              // Trade End Time

input group "Position Config";
input int Magic            = 8888;
input lot_methods lot_type = constant;              // how to calculate lot size? 
input int dollar_balance   = 100;                   // base account dollar for balance and equity calculation
input double lot_value     = 0.1;                   // lot size
input int sl_distance      = 10;                    // sl distance in pip
input tp_method tp_type = TP1_TP2_Trail;            // which tp to be active?
input int tp1_distance     = 20;                    // tp 1 distance in pip
input int tp2_distance     = 30;                    // tp 2 distance in pip
input int tp1_percent      = 50;                    // % percent of position to close at tp 1 
input int tp2_percent      = 30;                    // % percent of position to close at tp 2 

input group "Trail Config";
input int trail_percent    = 20;                    // % percent of position to close at trail 
input int trail_start_dist = 10;                    // Trail Start distance in pip 
input int trail_pip        = 30;                    // Trail distance in pips when trail start reached

input group "Risk free Config";
input bool use_rf          = false;                 // Enable Risk Free ?
input double rf_distance   = 5;                     // Price Distance from Entry (pip)


//--- global variables
double lot_size;                       // calculated initial lot size based on inputs
datetime last_trade;                   // last trade time -> checking rest time between trades
double calculated_box_size;            // last calculated box Size
double calculated_box_high;            // last calculated box high
double calculated_box_low;             // last calculated box low


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   if (TimeCurrent() > StringToTime("2025-04-01")){
      Print("License finished. Contact Support for Help");
      return (INIT_FAILED);
   }
   if (breakout_candles < 1)
   {
      Print("BreakOut Candles must be Greater than 1");
      return (INIT_FAILED);
   }
   
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
      check_box();
      totalbars = bars;
   }
   
   if (check_time())
   {
      if (check_spread())
      {
            check_bars();
      }
   }
      
   //--- trail and risk free part 
   if (PositionsTotal()>0){
      for (int i=0; i<PositionsTotal(); i++){
         ulong tikt = PositionGetTicket(i);
         if (PositionSelectByTicket(tikt)){
            //--- checking for risk free opportunity
            riskfree(tikt);
            
            if (PositionGetInteger(POSITION_MAGIC) == Magic){
               string type;
               if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) 
               {
                  type = "BUY";
                  //double sl = PositionGetDouble(POSITION_SL);
                  //if (SymbolInfoDouble(_Symbol, SYMBOL_BID) < sl){
                  //   trade.PositionClose(tikt);
                  //}
               }
               else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) 
               {
                  type = "SELL";
                  //double sl = PositionGetDouble(POSITION_SL);
                  //if (SymbolInfoDouble(_Symbol, SYMBOL_ASK) > sl){
                  //   trade.PositionClose(tikt);
                  //}
               }
               trailing(tikt, type);
            }
         }
      }
   }
}


//+------------------------------------------------------------------+
//| check time of market                                             |
//+------------------------------------------------------------------+
bool check_time(){
   if (TimeCurrent() >= StringToTime(trade_time_s) && TimeCurrent() <= StringToTime(trade_time_e))
   {
      
      if (MathAbs(iBarShift(_Symbol, PERIOD_CURRENT, last_trade)-iBarShift(_Symbol, PERIOD_CURRENT, TimeCurrent())) > rest || 
         iBarShift(_Symbol, PERIOD_CURRENT, last_trade) == -1)
      {
         return true;
      }
   }
   return false;
}


//+------------------------------------------------------------------+
//| check spread of market                                           |
//+------------------------------------------------------------------+
bool check_spread(){
   int spread = ( int )SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if (spread <= max_spread)
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| check box height and candles                                     |
//+------------------------------------------------------------------+
bool check_box(){
   // find box size of last X candles
   double 
      highest_point=0, 
      lowest_point=1000000000;
   
   if (height_method == high_low)
   {
      for (int i=0; i<=X; i++){
         double 
            high =iHigh(_Symbol, PERIOD_CURRENT, i+breakout_candles),
            low = iLow(_Symbol, PERIOD_CURRENT, i+breakout_candles);
         
         if (high > highest_point)
            highest_point = high;
         if (low < lowest_point)
            lowest_point = low;
      }
   }
   else 
   {
      for (int i=0; i<=X; i++){
         double 
            close = iClose(_Symbol, PERIOD_CURRENT, i+breakout_candles),
            open  = iOpen(_Symbol, PERIOD_CURRENT, i+breakout_candles),
            high  = close > open ? close : open,
            low   = close > open ? open : close;
         
         if (high > highest_point)
            highest_point = high;
         if (low < lowest_point)
            lowest_point = low;
      }
   }
   
   double box_size = highest_point - lowest_point;
   calculated_box_high = highest_point;
   calculated_box_low = lowest_point;
   
   // check if box size in user defined range
   if (box_size >= min_box_height*10*_Point && box_size <= max_box_height*10*_Point)
   {
      
      calculated_box_size = box_size;
      Print("box size is ok ", calculated_box_size);
      return true;
   }
   
   calculated_box_size = -1;
   return false;
}

//+------------------------------------------------------------------+
//| check last X candles for a setup                                 |
//+------------------------------------------------------------------+
void check_bars(){
   // find bar size in cum-sum approach
   double
      highest_point  = 0,
      lowest_point   = 1000000000;
   
   /*if (bcm == high_low && breakout_candles > 1)
   {
      double open = iOpen(_Symbol, PERIOD_CURRENT, breakout_candles);
      
      for (int i=0;  i<breakout_candles-1;  i++)
      {
         double 
            high = iHigh(_Symbol, PERIOD_CURRENT, i),
            low  = iLow(_Symbol, PERIOD_CURRENT, i);
         
         if (high > highest_point) 
            highest_point = high;
         if (low < lowest_point) 
            lowest_point = low;
      }
   }
   else
   {
      for (int i=0;  i<breakout_candles;  i++)
      {
         double 
            close = iClose(_Symbol, PERIOD_CURRENT, i),
            open = iOpen(_Symbol, PERIOD_CURRENT, i),
            high = close > open ? close : open,
            low  = close > open ? open : close;
      
         if (high > highest_point) 
            highest_point = high;
         if (low < lowest_point) 
            lowest_point = low;
      }
   }
   
   double bar_size = highest_point-lowest_point;*/
   
   //--- update 1.60 
   double open = iOpen(_Symbol, PERIOD_CURRENT, breakout_candles-1);
   double close = iClose(_Symbol, PERIOD_CURRENT, 0);
   double bar_size = MathAbs(open-close);
   
   // check bar size vs box size
   if (calculated_box_size > 0 && bar_size != 0)
   {
      
      if (bar_size >= calculated_box_size*box_percent/100)
      {
         //--- calculate lot size
         if (lot_type == 1) lot_size = lot_value;
         else lot_size = lot_value*(AccountInfoDouble(ACCOUNT_BALANCE)/dollar_balance);
         
         Print("bar size = ", bar_size);
         
         //--- open positions based on breakout side
         if (calculated_box_high < close && open < close && open > calculated_box_low)
         {
            open_position("BUY");
            last_trade = TimeCurrent();
            datetime t1 = iTime(_Symbol, PERIOD_CURRENT, X+breakout_candles);
            datetime t2 = iTime(_Symbol, PERIOD_CURRENT, breakout_candles);
            double p1 = calculated_box_high;
            double p2 = calculated_box_low;
            draw_box(t1, p1, t2, p2);
         }
         else if (calculated_box_low > close && open > close && open < calculated_box_high)
         {
            open_position("SELL");
            last_trade = TimeCurrent();
            datetime t1 = iTime(_Symbol, PERIOD_CURRENT, X+breakout_candles);
            datetime t2 = iTime(_Symbol, PERIOD_CURRENT, breakout_candles);
            double p1 = calculated_box_high;
            double p2 = calculated_box_low;
            draw_box(t1, p1, t2, p2);
         }
         
      }
   }      
}


//+------------------------------------------------------------------+
//| Draw Box on Chart                                                |
//+------------------------------------------------------------------+
void draw_box(datetime t1, double p1, datetime t2, double p2){
   
   long chart_id = ChartID();
   string obj_name = "BOX_"+TimeToString(t2);
   
   if (ObjectCreate(chart_id, obj_name, OBJ_RECTANGLE, 0, t1, p1, t2, p2))
   {
      ObjectSetInteger(chart_id, obj_name, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(chart_id, obj_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(chart_id, obj_name, OBJPROP_FILL, false);
      ObjectSetInteger(chart_id,obj_name, OBJPROP_COLOR, clrGold);
      
      string size_obj = "Box Size -- "+ (string)NormalizeDouble(calculated_box_high-calculated_box_low,3);
      if (ObjectCreate(chart_id, size_obj, OBJ_TEXT, 0, t1+PeriodSeconds(PERIOD_CURRENT), (double)p1 ))
      {
         ObjectSetString(chart_id, size_obj,OBJPROP_TEXT,"Pip Change: "+(string)NormalizeDouble((calculated_box_high-calculated_box_low)/(_Point*10),3) ); 
         ObjectSetInteger(chart_id, size_obj, OBJPROP_COLOR, clrGold);
      }
      
   }
   
}



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
         return true;
      }
      
   } else {
      if (trade.Sell(lots, _Symbol, 0, sl, tp, comment))
      {
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
      if (ask > PositionGetDouble(POSITION_PRICE_OPEN)+(trail_start_dist*10*_Point)){
         if (ask-curr_sl > trail_pip*10*_Point){
            trade.PositionModify(tikt, ask - trail_pip*10*_Point, curr_tp);
            Print("changed buy trailed to ", ask - trail_pip*10*_Point);
         }
      }
   } else {
      if (bid < PositionGetDouble(POSITION_PRICE_OPEN)-(trail_start_dist*10*_Point)){
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