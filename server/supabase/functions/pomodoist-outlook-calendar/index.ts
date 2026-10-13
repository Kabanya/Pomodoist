import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serveCalendar } from "../_shared/calendar/serve.ts";
serveCalendar("outlook");
