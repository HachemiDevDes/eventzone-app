import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { initializeApp, cert } from 'npm:firebase-admin/app'
import { getMessaging } from 'npm:firebase-admin/messaging'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Initialize Firebase Admin lazily to avoid cold start errors if already initialized
let firebaseApp: any = null;

function getFirebaseApp() {
  if (!firebaseApp) {
    // Option 1: Full JSON string in FIREBASE_SERVICE_ACCOUNT or FIREBASE_SERVICE_ACCOUNT_KEY
    const rawJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || Deno.env.get('FIREBASE_SERVICE_ACCOUNT_KEY');
    if (rawJson && rawJson.trim()) {
      try {
        const parsed = typeof rawJson === 'string' ? JSON.parse(rawJson.trim()) : rawJson;
        firebaseApp = initializeApp({
          credential: cert(parsed),
        });
        return firebaseApp;
      } catch (err: any) {
        console.error("Failed to parse FIREBASE_SERVICE_ACCOUNT JSON:", err);
      }
    }

    // Option 2: Individual environment variables
    const projectId = Deno.env.get('FIREBASE_PROJECT_ID') || 'eventzone-app-f4984';
    const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
    const rawPrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY');

    if (!clientEmail || !rawPrivateKey) {
      throw new Error(
        "Firebase Admin credentials are missing. Please add FIREBASE_SERVICE_ACCOUNT in Supabase Dashboard -> Project Settings -> Edge Functions -> Secrets."
      );
    }

    const privateKey = rawPrivateKey.replace(/\\n/g, '\n');
    firebaseApp = initializeApp({
      credential: cert({
        projectId,
        clientEmail,
        privateKey,
      }),
    });
  }
  return firebaseApp;
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { target, title, message, data } = await req.json()

    // 1. Validate inputs
    if (!title || !message || !target) {
      throw new Error("Missing required parameters: title, message, or target")
    }

    // 2. Initialize Supabase
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const isBroadcast = target === 'All Users' || target === 'Paid Users' || target === 'Free Users';

    let paidUserIds = new Set<string>();
    if (target === 'Paid Users' || target === 'Free Users') {
      const { data: subs } = await supabaseClient
        .from('subscriptions')
        .select('user_id')
        .eq('status', 'Active')
        .gt('end_date', new Date().toISOString())

      const { data: paidProfiles } = await supabaseClient
        .from('profiles')
        .select('id')
        .gt('subscription_end_date', new Date().toISOString())

      paidUserIds = new Set([
        ...(subs?.map((s) => s.user_id) || []),
        ...(paidProfiles?.map((p) => p.id) || [])
      ]);
    }

    // 3. Fetch FCM tokens (optimized by user_id for direct messages)
    let tokensQuery = supabaseClient
      .from('user_fcm_tokens')
      .select('user_id, token');

    if (!isBroadcast) {
      tokensQuery = tokensQuery.eq('user_id', target);
    }

    const { data: tokensData, error: tokensError } = await tokensQuery;

    if (tokensError) {
      throw new Error(`Failed to fetch FCM tokens: ${tokensError.message}`);
    }

    // 4. Filter tokens based on target
    let tokensToSend: string[] = []
    
    if (tokensData && tokensData.length > 0) {
      for (const t of tokensData) {
        if (!t.token || typeof t.token !== 'string' || !t.token.trim()) continue;
        
        if (target === 'All Users') {
          tokensToSend.push(t.token.trim())
        } else if (target === 'Paid Users') {
          if (paidUserIds.has(t.user_id)) tokensToSend.push(t.token.trim())
        } else if (target === 'Free Users') {
          if (!paidUserIds.has(t.user_id)) tokensToSend.push(t.token.trim())
        } else if (target === t.user_id) {
          tokensToSend.push(t.token.trim())
        }
      }
    }

    // Deduplicate tokens
    tokensToSend = [...new Set(tokensToSend)]

    if (tokensToSend.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: "No matching registered devices with push tokens." }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. Send via Firebase Admin
    getFirebaseApp();
    const messaging = getMessaging();

    const BATCH_SIZE = 500;
    let successCount = 0;
    let failureCount = 0;

    for (let i = 0; i < tokensToSend.length; i += BATCH_SIZE) {
      const batchTokens = tokensToSend.slice(i, i + BATCH_SIZE);
      const payload: any = {
        notification: {
          title: title,
          body: message,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'high_importance_channel',
            sound: 'default',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
        tokens: batchTokens,
      };

      if (data && typeof data === 'object') {
        payload.data = Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v ?? '')])
        );
      }

      const response = await messaging.sendEachForMulticast(payload);
      successCount += response.successCount;
      failureCount += response.failureCount;
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: `Notification sent to ${successCount} devices (Failed: ${failureCount})` 
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: any) {
    console.error("Error sending push notification:", error)
    return new Response(
      JSON.stringify({ error: error.message, stack: error.stack }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  }
})
