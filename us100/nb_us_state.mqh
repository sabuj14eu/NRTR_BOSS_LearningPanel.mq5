#define NB_NEWS_UNKNOWN 0   // calendar off / unavailable / empty: UNKNOWN, never "no news"
#define NB_NEWS_CLEAR   1   // calendar read: no high-impact USD event inside the window
#define NB_NEWS_WINDOW  2   // a high-impact USD event inside the window

int      g_usNewsState = NB_NEWS_UNKNOWN;
string   g_usNewsTxt = "UNKNOWN - CALENDAR NOT READ YET";
string   g_usNewsName = "";
datetime g_usNewsTime = 0;
datetime g_usNewsAt = 0;

