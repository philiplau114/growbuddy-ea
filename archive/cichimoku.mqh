// CIchimoku - lightweight Ichimoku helper class
// - Init() creates iIchimoku handle (call in OnInit)
// - Release() releases handle (call in OnDeinit)
// - GetValues(shift, &tenkan,&kijun,&sa,&sb,&chikou) reads buffers for given shift
// - Helper queries: IsKumoBullish(shift), FutureKumoBullish(shift)
class CIchimoku
  {
private:
   int                m_handle;
   string             m_symbol;
   ENUM_TIMEFRAMES    m_tf;
   int                m_tenkan;
   int                m_kijun;
   int                m_senkouB;
   bool               m_ready;

public:
   // constructor-like initializer
   void CIchimoku()
     {
      m_handle = INVALID_HANDLE;
      m_ready = false;
     }

   // initialize (create handle) - call in OnInit
   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const int tenkan=9, const int kijun=26, const int senkouB=52)
     {
      m_symbol = symbol;
      m_tf = tf;
      m_tenkan = tenkan;
      m_kijun = kijun;
      m_senkouB = senkouB;
      m_handle = iIchimoku(m_symbol, m_tf, m_tenkan, m_kijun, m_senkouB);
      if(m_handle == INVALID_HANDLE)
        {
         PrintFormat("CIchimoku::Init - failed to create iIchimoku handle for %s tf=%d tenkan=%d kijun=%d senkouB=%d", m_symbol, m_tf, m_tenkan, m_kijun, m_senkouB);
         return(false);
        }
      m_ready = true;
      return(true);
     }

   // release indicator handle - call in OnDeinit
   void Release()
     {
      if(m_handle != INVALID_HANDLE)
        {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
        }
      m_ready = false;
     }

   // get values at given shift: tenkan, kijun, senkouA, senkouB, chikou
   bool GetValues(const int shift, double &tenkan_v, double &kijun_v, double &senkouA_v, double &senkouB_v, double &chikou_v)
     {
      if(!m_ready) return(false);
      double buf[];
      // Tenkan (buffer 0)
      if(CopyBuffer(m_handle, 0, shift, 1, buf) <= 0) return(false);
      tenkan_v = buf[0];
      // Kijun (buffer 1)
      if(CopyBuffer(m_handle, 1, shift, 1, buf) <= 0) return(false);
      kijun_v = buf[0];
      // SenkouA (buffer 2)
      if(CopyBuffer(m_handle, 2, shift, 1, buf) <= 0) return(false);
      senkouA_v = buf[0];
      // SenkouB (buffer 3)
      if(CopyBuffer(m_handle, 3, shift, 1, buf) <= 0) return(false);
      senkouB_v = buf[0];
      // Chikou (buffer 4) - chikou span value at shift
      if(CopyBuffer(m_handle, 4, shift, 1, buf) <= 0)
        {
         // fallback: approximate with shifted close
         chikou_v = iClose(m_symbol, m_tf, shift + m_tenkan);
        }
      else
        {
         chikou_v = buf[0];
        }
      return(true);
     }

   // helper: is current kumo bullish at shift (SenkouA > SenkouB)
   bool IsKumoBullish(const int shift)
     {
      double sa, sb, t,k,ch;
      if(!GetValues(shift,t,k,sa,sb,ch)) return(false);
      return (sa > sb);
     }

   // helper: Tenkan above Kumo check at shift
   bool IsTenkanAboveKumo(const int shift)
     {
      double ten,kij,sa,sb,ch;
      if(!GetValues(shift,ten,kij,sa,sb,ch)) return(false);
      return (ten > MathMax(sa, sb));
     }

   // helper: Tenkan below Kumo
   bool IsTenkanBelowKumo(const int shift)
     {
      double ten,kij,sa,sb,ch;
      if(!GetValues(shift,ten,kij,sa,sb,ch)) return(false);
      return (ten < MathMin(sa, sb));
     }

   // future kumo bullish: compare current senkou with previous (shift+1)
   bool FutureKumoBullish(const int shift)
     {
      double ten1,kij1,sa_now,sb_now,ch1;
      if(!GetValues(shift,ten1,kij1,sa_now,sb_now,ch1)) return(false);
      double ten2,kij2,sa_prev,sb_prev,ch2;
      if(!GetValues(shift+1,ten2,kij2,sa_prev,sb_prev,ch2)) return(false);
      return (sa_now > sb_now) && (sa_prev <= sb_prev);
     }

   // future kumo bearish
   bool FutureKumoBearish(const int shift)
     {
      double ten1,kij1,sa_now,sb_now,ch1;
      if(!GetValues(shift,ten1,kij1,sa_now,sb_now,ch1)) return(false);
      double ten2,kij2,sa_prev,sb_prev,ch2;
      if(!GetValues(shift+1,ten2,kij2,sa_prev,sb_prev,ch2)) return(false);
      return (sa_now < sb_now) && (sa_prev >= sb_prev);
     }

  }; // end class CIchimoku