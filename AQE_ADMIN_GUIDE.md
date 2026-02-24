# AI Quotation Engine (AQE) — Admin & Developer Configuration Guide

## Overview

The AQE package installs 7 custom objects, 26 Apex classes, 4 LWC components, 1 Named Credential,
and 2 permission sets. The engine works in three layers:

1. **Salesforce (Apex)** — reads your rules, validates every price deterministically, creates quotes
2. **Node.js backend** — sends your rules + prompt to Claude (Anthropic AI), tokenises PII before it leaves Salesforce
3. **LWC UI** — the quote generator panel and admin dashboard

```
Sales User types prompt
        ↓
aqeQuoteGeneratorMain (LWC)
        ↓
AQE_QuoteController (@AuraEnabled)
        ↓
AQE_RuleEngine  →  loads AI rules from custom objects
        ↓
AQE_LLMService  →  calls Named Credential → Node.js → Claude API
        ↓
AQE_ValidationEngine  →  recalculates every price independently
        ↓
AQE_ApprovalEngine  →  checks discount/deal thresholds
        ↓
Adapter (Standard / CPQ / Revenue)  →  creates Quote + Lines
```

---

## Section 1 — Install the Package

**Install URL:**
```
https://login.salesforce.com/packaging/installPackage.apexp?p0=04tg50000003jobAAA
```

Steps:
1. Log in to your org (`rajpriyanka@cpq.com`) in a browser
2. Paste the URL above into the address bar
3. Choose **Install for All Users**
4. Click **Install** and wait ~2 minutes

After install, all custom objects and Apex classes appear in Setup.

---

## Section 2 — Enable Salesforce Quotes

**Path:** `Setup → Search "Quote Settings" → Quote Settings`

Turn on: **Enable Quotes** ✅

This activates the `Quote` and `QuoteLineItem` standard objects that the Standard Adapter uses.
Without this, the Standard adapter will fail on every quote creation attempt.

---

## Section 3 — Configure the Named Credential

The Named Credential tells Salesforce where your Node.js backend lives.
Every AI callout routes through it — no URL is hardcoded in Apex.

**Path:** `Setup → Security → Named Credentials → AQE Backend → Edit`

| Field | What to Enter |
|---|---|
| Label | AQE Backend *(leave as-is)* |
| URL / Endpoint | Your Node.js server URL, e.g. `https://your-domain.com` or `https://abc123.ngrok.io` |
| Identity Type | Anonymous |
| Authentication Protocol | No Authentication |
| Allow Merge Fields in Body | ✅ checked |

> **Local testing tip:** Run the Node.js backend on your machine and expose it with
> `ngrok http 3000` — copy the `https://` ngrok URL into the endpoint field.

---

## Section 4 — Configure the AI Engine Custom Setting

This is the master switch for the entire engine. All configurable parameters live here — nothing is hardcoded.

**Path:** `Setup → Custom Code → Custom Settings → AI Engine Config → Manage → New`

*(If a record already exists, click **Edit** next to it)*

| Field Label | Field API Name | What It Controls | Recommended Value |
|---|---|---|---|
| Engine Active | `Engine_Active__c` | Master on/off switch. When false, the LWC shows "AI Engine Disabled" and blocks all generation | `true` |
| Cloud Environment | `Cloud_Environment__c` | Tells AdapterFactory which quote objects to use. Auto-set by "Re-detect" button | `Standard_Salesforce` *(or run Re-detect)* |
| LLM Model | `LLM_Model__c` | Claude model ID sent to your Node.js backend | `claude-sonnet-4-6` |
| LLM Endpoint URL | `LLM_Endpoint_URL__c` | Optional override — leave blank if Node.js handles routing | *(leave blank)* |
| Max Quote Lines | `Max_Quote_Lines__c` | Lines above this number switch to async Queueable processing | `30` |
| Enable PII Tokenisation | `Enable_PII_Tokenisation__c` | Replaces emails, phone numbers, Salesforce IDs with tokens before sending to LLM | `true` |
| Callout Timeout Seconds | `Callout_Timeout_Seconds__c` | HTTP timeout for the LLM callout | `120` |

**Cloud Environment values accepted by the engine:**
- `Standard_Salesforce` — uses Quote / QuoteLineItem
- `CPQ_Cloud` — uses SBQQ__Quote__c / SBQQ__QuoteLine__c (requires Salesforce CPQ installed)
- `Revenue_Cloud` — uses Order / OrderItem

**Auto-detect instead of typing manually:**
After adding the `aqeCloudSetupWizard` LWC to a page (Section 6), click the
**Re-detect Environment** button — it queries your org's schema and sets
`Cloud_Environment__c` automatically.

---

## Section 5 — Assign Permission Sets

**Path:** `Setup → Users → Permission Sets`

Two permission sets are installed:

### AQE Admin
Assign to: admins, ops managers, anyone who configures rules

| What It Grants |
|---|
| Full CRUD on `AI_Pricing_Rule__c`, `AI_Product_Rule__c`, `AI_Discount_Rule__c`, `AI_Approval_Policy__c`, `AI_Delegate_Config__c` |
| Read-only on `AI_Transaction_Log__c` (audit trail) |
| Access to `AQE_QuoteController` and `AQE_CloudDetector` Apex classes |
| Access to `AI_Engine_Config__c` custom setting |

**To assign:**
1. Click **AQE Admin** → **Manage Assignments** → **Add Assignment**
2. Select your admin user → **Assign**

### AQE User
Assign to: all sales reps who will generate quotes

| What It Grants |
|---|
| Read-only on all rule objects |
| Create on `AI_Transaction_Log__c` (own logs only) |
| Access to `AQE_QuoteController` Apex class |

---

## Section 6 — Add LWC Components to Lightning Pages

### Quote Generator — `aqeQuoteGeneratorMain`

Add to the **Account** or **Opportunity** record page so sales users can generate
quotes in context.

**Path:** Go to any Account record → click the gear icon (⚙) → **Edit Page**

1. In the component panel on the left, search for `aqeQuoteGeneratorMain`
2. Drag it onto the page layout (right column recommended)
3. Click **Save** → **Activate** → choose who sees it

The component auto-reads `recordId` and `objectApiName` from the record page —
it knows which account or opportunity the user is on.

**What sales users will see:**
- Engine status badge (Active / Disabled)
- A textarea to type the quote description in plain English
- **Generate Quote** button
- A live quote preview table with inline editing for quantity and discount
- Approval warnings if the quote needs routing
- A "View Quote Record" button to navigate to the created Quote

### Admin Setup Wizard — `aqeCloudSetupWizard`

Add to an **App Page** or **Home Page** for admin visibility.

**Path:** `App Launcher → any app → gear icon → Edit Page` or create a new App Page

1. Search for `aqeCloudSetupWizard`
2. Drop it onto the canvas
3. Save and activate

**What admins will see:**
- Engine Active status (green / red)
- Detected Cloud Environment
- Backend Service reachability (health check ping)
- Current LLM model name
- Max sync lines setting
- PII Tokenisation on/off
- **Re-detect Environment** button
- **Refresh Status** button
- Setup checklist

---

## Section 7 — Configure AI Pricing Rules

**Where:** `App Launcher → AI Pricing Rules`
*(or Setup → Object Manager → AI_Pricing_Rule__c → Records)*

Pricing rules tell the AI **how to calculate prices** for specific products.
They are written in **natural language** — the LLM reads them as part of its system prompt.

### All Fields Explained

| Field Label | API Name | Type | What to Enter |
|---|---|---|---|
| Name | `Name` | Text(80) | Descriptive rule name, e.g. `Enterprise Volume Discount — Laptops` |
| Product Code | `Product_Code__c` | Text(255) | Which products this applies to. Use `*` for all, `PROD-01,PROD-02` for specific ones, or blank for all |
| Active | `Active__c` | Checkbox | ✅ tick to enable |
| Rule Category | `Rule_Category__c` | Picklist | `Volume`, `Discount`, `Bundle`, `Custom`, `Override` |
| Priority | `Priority__c` | Number | Integer — lower numbers run first. Use `1` for highest priority |
| Condition Text | `Condition_Text__c` | Long Text(131072) | Natural language description of **when** this rule applies |
| Formula Text | `Formula_Text__c` | Long Text(131072) | Natural language description of **what** the rule calculates |
| Effective Date | `Effective_Date__c` | Date | Date the rule becomes active (blank = always active) |
| Expiry Date | `Expiry_Date__c` | Date | Date the rule stops applying (blank = never expires) |

### Example Records

**Example 1 — Volume Discount**
```
Name:           Volume Discount - Laptops 50+
Product Code:   LAPTOP-PRO-15
Active:         true
Rule Category:  Volume
Priority:       1
Condition Text: When the quantity of Laptop Pro 15 units is 50 or more on the quote
Formula Text:   Apply a 10% discount to the unit price.
                unit_price = list_price * 0.90
                total_price = unit_price * quantity
Effective Date: (leave blank)
Expiry Date:    (leave blank)
```

**Example 2 — Enterprise Discount**
```
Name:           Enterprise Account Discount - All Products
Product Code:   *
Active:         true
Rule Category:  Discount
Priority:       5
Condition Text: When the account type is Enterprise or the quote description
                mentions the word "enterprise"
Formula Text:   Apply a standard 5% enterprise discount on top of any existing
                line discounts.
                unit_price = list_price * (1 - total_discount_percent / 100)
Effective Date: (leave blank)
Expiry Date:    (leave blank)
```

**Example 3 — Promotional Override**
```
Name:           Q4 Year-End Promo - Warranties
Product Code:   EXT-WARRANTY
Active:         true
Rule Category:  Override
Priority:       2
Condition Text: Active during the Q4 promotional period (October 1 to December 31)
Formula Text:   Override warranty price to $99.00 flat regardless of standard list price.
                unit_price = 99.00
                total_price = 99.00 * quantity
Effective Date: 01/10/2025
Expiry Date:    31/12/2025
```

> **How the engine uses these records:**
> `AQE_RuleEngine.getApplicablePricingRules()` queries all Active rules, filters by
> date range and product code match, then serialises `Condition_Text__c` and
> `Formula_Text__c` into JSON that becomes the LLM system prompt.
> The LLM reads them as instructions when generating your quote.

---

## Section 8 — Configure AI Product Rules

**Where:** `App Launcher → AI Product Rules`

Product rules control **bundle logic** — what happens when certain products appear
together (mandatory add-ons, incompatibility checks, bundle discounts).

### All Fields Explained

| Field Label | API Name | Type | What to Enter |
|---|---|---|---|
| Name | `Name` | Text(80) | Rule name, e.g. `Laptop + Warranty Bundle` |
| Active | `Active__c` | Checkbox | ✅ |
| Rule Type | `Rule_Type__c` | Picklist | `Bundle`, `Mandatory`, `Incompatible`, `Recommendation` |
| Primary Product Code | `Primary_Product_Code__c` | Text(255) | The "trigger" product code |
| Related Product Codes | `Related_Product_Codes__c` | Long Text | Comma-separated product codes of related products |
| Rule Text | `Rule_Text__c` | Long Text(131072) | Natural language description of the rule logic |
| Bundle Discount Percent | `Bundle_Discount_Percent__c` | Number | Discount % applied when both products are on the same quote |
| Priority | `Priority__c` | Number | Lower runs first |

### Example Records

**Example 1 — Bundle Discount**
```
Name:                   Laptop + Warranty Bundle
Rule Type:              Bundle
Primary Product Code:   LAPTOP-PRO-15
Related Product Codes:  EXT-WARRANTY
Bundle Discount %:      5
Rule Text:              When a Laptop Pro 15 and Extended Warranty appear on the same
                        quote, apply an additional 5% bundle discount to the warranty line.
```

**Example 2 — Mandatory Add-on**
```
Name:                   Software Requires OS License
Rule Type:              Mandatory
Primary Product Code:   CREATIVE-SUITE-PRO
Related Product Codes:  OS-LICENSE-WIN,OS-LICENSE-MAC
Bundle Discount %:      (blank)
Rule Text:              Creative Suite Pro requires an operating system license. If
                        OS-LICENSE-WIN or OS-LICENSE-MAC is not already on the quote,
                        add one OS-LICENSE-WIN at list price automatically.
```

**Example 3 — Incompatibility**
```
Name:                   Standard vs Enterprise License Conflict
Rule Type:              Incompatible
Primary Product Code:   LICENSE-STANDARD
Related Product Codes:  LICENSE-ENTERPRISE
Bundle Discount %:      (blank)
Rule Text:              Standard and Enterprise licenses cannot appear on the same quote.
                        If both are present, flag an error and ask the user to choose one.
```

---

## Section 9 — Configure AI Discount Rules

**Where:** `App Launcher → AI Discount Rules`

Discount rules define the **financial guard rails** — maximum allowed discounts,
approval thresholds, and whether discounts can stack.

### All Fields Explained

| Field Label | API Name | Type | What to Enter |
|---|---|---|---|
| Name | `Name` | Text(80) | Rule name |
| Active | `Active__c` | Checkbox | ✅ |
| Discount Type | `Discount_Type__c` | Picklist | `Percentage`, `Flat Amount`, `Override` |
| Discount Value | `Discount_Value__c` | Number | Default discount value (% or flat amount) the LLM should apply |
| **Max Discount Percent** | `Max_Discount_Percent__c` | Number | **Hard ceiling — Apex ValidationEngine enforces this. LLM cannot exceed it.** |
| **Approval Required Threshold** | `Approval_Required_Threshold__c` | Number | If discount exceeds this %, ApprovalEngine routes the quote |
| Stackable | `Stackable__c` | Checkbox | Whether this discount can combine with other discounts |
| Condition Text | `Condition_Text__c` | Long Text | Natural language — when this discount rule applies (LLM context) |
| Effective Date | `Effective_Date__c` | Date | |
| Expiry Date | `Expiry_Date__c` | Date | |

### How the Engine Enforces These

- `Max_Discount_Percent__c` is read by `AQE_ValidationEngine.validateQuoteLines()` and
  **automatically clamps** any line where discount exceeds the max — the LLM cannot override this.
  This is a deterministic Apex check, not an AI decision.
- `Approval_Required_Threshold__c` is read by `AQE_ApprovalEngine.evaluate()` — if breached,
  the quote is automatically submitted to the Salesforce Approval Process.
- `Discount_Value__c` and `Condition_Text__c` are sent to the LLM as context so it knows
  what discounts to offer based on the user's request.

### Example Records

**Example 1 — Standard Discount Cap**
```
Name:                          Standard Discount Policy
Discount Type:                 Percentage
Discount Value:                10
Max Discount Percent:          25
Approval Required Threshold:   20
Stackable:                     true
Condition Text:                Standard commercial discount applicable to all
                               non-enterprise accounts for regular purchases
```

**Example 2 — Enterprise Discount**
```
Name:                          Enterprise Volume Policy
Discount Type:                 Percentage
Discount Value:                15
Max Discount Percent:          40
Approval Required Threshold:   30
Stackable:                     true
Condition Text:                Enterprise accounts with deal value over $50,000
                               or quantities over 100 units per line
```

**Example 3 — End of Quarter Push (date-limited)**
```
Name:                          Q4 Closeout Special
Discount Type:                 Percentage
Discount Value:                20
Max Discount Percent:          20
Approval Required Threshold:   20
Stackable:                     false
Effective Date:                01/12/2025
Expiry Date:                   31/12/2025
Condition Text:                Year-end closeout discount. Cannot be combined
                               with any other discounts on the same quote.
```

---

## Section 10 — Configure AI Approval Policies

**Where:** `App Launcher → AI Approval Policies`

Approval policies tell the engine **when to submit a quote for Salesforce approval**
and **which approval chain to use**.

> **Important:** These records control the *triggering* of a Salesforce Approval Process.
> You must also have a matching Approval Process configured at
> `Setup → Process Automation → Approval Processes` on the Quote object.
> The `Approval_Chain__c` value here must **exactly match** the Approval Process API name there.

### All Fields Explained

| Field Label | API Name | Type | What to Enter |
|---|---|---|---|
| Name | `Name` | Text(80) | Policy name |
| Active | `Active__c` | Checkbox | ✅ |
| Priority | `Priority__c` | Number | Lower = evaluated first. First matching policy wins |
| Min Discount Threshold | `Min_Discount_Threshold__c` | Number | If effective discount % on the whole quote is ≥ this, approval triggers |
| Min Deal Value | `Min_Deal_Value__c` | Currency | If net quote total is ≥ this amount, approval triggers |
| **Approval Chain** | `Approval_Chain__c` | Text(255) | **Exact API name of the Salesforce Approval Process to submit to** |
| Trigger Condition | `Trigger_Condition__c` | Long Text | Natural language description of when this policy applies |
| Auto Approve Condition | `Auto_Approve_Condition__c` | Long Text | When to bypass approval automatically |

### Example Records

**Example 1 — High Discount Approval**
```
Name:                     High Discount Policy
Active:                   true
Priority:                 1
Min Discount Threshold:   20
Min Deal Value:           (blank — trigger on discount % alone)
Approval Chain:           Quote_Standard_Approval
Trigger Condition:        Quote has an effective discount of 20% or more across all lines
Auto Approve Condition:   (blank)
```

**Example 2 — High Value Deal**
```
Name:                     Enterprise Deal Policy
Active:                   true
Priority:                 2
Min Discount Threshold:   (blank)
Min Deal Value:           100000
Approval Chain:           Quote_Executive_Approval
Trigger Condition:        Net deal value exceeds $100,000
Auto Approve Condition:   Auto-approve if account type is Strategic and
                          deal value is under $150,000
```

> **How it works in code:**
> `AQE_ApprovalEngine.evaluate()` loops through all active policies ordered by Priority.
> The first policy where `effectiveDiscountPercent >= Min_Discount_Threshold__c`
> OR `netTotal >= Min_Deal_Value__c` matches.
> It then calls `adapter.submitForApproval(quoteId)` using Salesforce's
> `Approval.ProcessSubmitRequest` API.

---

## Section 11 — Configure Approval Delegates (Optional)

**Where:** `App Launcher → AI Delegate Configs`

If an approver is on leave, create a delegate record so the approval gets re-routed
without manual intervention.

| Field Label | API Name | What to Enter |
|---|---|---|
| Active | `Active__c` | ✅ |
| Primary Approver Role | `Primary_Approver_Role__c` | Salesforce Role API Name of the original approver |
| Delegate Approver Role | `Delegate_Approver_Role__c` | Salesforce Role API Name of the person covering |
| Delegation Start | `Delegation_Start__c` | DateTime when delegation begins |
| Delegation End | `Delegation_End__c` | DateTime when delegation ends |
| Escalation Timeout Hours | `Escalation_Timeout_Hours__c` | Hours before unactioned approvals escalate |

---

## Section 12 — Set Up the Node.js Backend

This is a fully manual step — you deploy the Node.js server independently
and then paste its public URL into the Named Credential.

### What It Does

- Receives the quote prompt + rules context from Salesforce (via Named Credential callout)
- Tokenises PII (emails, phone numbers, Salesforce IDs) before sending to Claude
- Calls Anthropic Claude API with a structured system prompt containing your rules
- Returns structured JSON (quote lines with product codes, quantities, prices, discounts)
- Runs a second server-side price validation pass before returning the response

### File Structure

```
backend/
├── server.js                   ← Express app entry point (start here)
├── package.json                ← npm dependencies
├── .env.example                ← copy to .env and fill in your values
├── config/
│   └── index.js                ← all config read from environment variables
├── middleware/
│   ├── auth.js                 ← validates X-AQE-OrgId header from Salesforce
│   └── logger.js               ← Winston structured logging
└── services/
    ├── llmOrchestrator.js      ← calls Anthropic SDK, builds system prompt
    ├── piiTokenizer.js         ← tokenises / detokenises PII
    └── ruleValidator.js        ← server-side price re-validation (mirrors Apex)
```

### API Endpoints

| Method | Path | Auth Required | Purpose |
|---|---|---|---|
| GET | `/api/health` | No | Health check — called by aqeCloudSetupWizard |
| POST | `/api/quote/generate` | Yes (X-AQE-OrgId header) | Generate quote from prompt |

### Setup Steps

**Step 1 — Install dependencies**
```bash
cd backend
npm install
```

**Step 2 — Create your .env file**
```bash
cp .env.example .env
```

Edit `.env` with your real values:
```
# Anthropic Claude API
LLM_PROVIDER=anthropic
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
LLM_MODEL=claude-sonnet-4-6
LLM_MAX_TOKENS=4096
LLM_TEMPERATURE=0.1

# Security — paste your Salesforce Org ID here
# Find it: run "sf org display --target-org rajpriyanka@cpq.com" → look for "id"
ALLOWED_ORG_IDS=00DWU00000iSk9r2AC

# Rate limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=20

# Server
PORT=3000
NODE_ENV=production
```

**Step 3 — Start the server**
```bash
node backend/server.js
```

For production use `pm2`:
```bash
npm install -g pm2
pm2 start backend/server.js --name aqe-backend
pm2 save
```

**Step 4 — Verify health endpoint**
```bash
curl https://your-backend-url.com/api/health
# Expected response:
# {"status":"ok","provider":"anthropic","model":"claude-sonnet-4-6"}
```

**Step 5 — Update the Named Credential**
Go back to Section 3 and paste your server URL into the AQE Backend Named Credential endpoint.

### Where to Get Your Anthropic API Key

1. Go to `https://console.anthropic.com`
2. Sign in → **API Keys** → **Create Key**
3. Copy the key (starts with `sk-ant-`) into your `.env` file

### Where to Find Your Salesforce Org ID

Run this in a terminal:
```bash
sf org display --target-org rajpriyanka@cpq.com
```
Look for the `id` field — it starts with `00D`. Paste it into `ALLOWED_ORG_IDS`.

---

## Section 13 — Verify the Full Installation

### Check via the Setup Wizard

On the page where you added `aqeCloudSetupWizard`, you should see:

| Card | Expected State |
|---|---|
| Engine Status | **Active** (green icon) |
| Cloud Environment | **Standard_Salesforce** |
| Backend Service | **Reachable** (green icon) |
| LLM Model | **claude-sonnet-4-6** |
| Max Sync Lines | **30** |
| PII Tokenisation | **Enabled** |

If **Backend Service** shows Unreachable:
- The Named Credential endpoint URL is wrong
- The Node.js server is not running
- Test manually: `curl https://your-url/api/health`

### Generate Your First Test Quote

1. Go to any **Account** record in Salesforce
2. Find the **AI Quote Generator** panel (if not visible, add the LWC from Section 6)
3. Type a test prompt such as:
   ```
   Create a quote for 50 Laptop Pro 15 units and 50 extended warranties
   with a 12% enterprise discount for this account
   ```
4. Click **Generate Quote**
5. The quote preview table will appear — you can:
   - Edit quantity and discount inline
   - Remove lines you don't want
   - Click **View Quote Record** to navigate to the created Quote
6. Check the **Quotes** related list on the Account — a new Quote record should appear

### Check the Audit Log After Each Generation

**Path:** `App Launcher → AI Transaction Logs`

Every call to the engine creates a record here. After your test, open it to see:

| Field | What to Check |
|---|---|
| Processing Status | Should be `Success` |
| Processing Time Ms | Typically 3,000 – 8,000 ms for a normal quote |
| Quote ID | Verify it matches the Quote record created |
| Validation Errors | Should be blank for a successful quote |
| Rules Applied | Lists which rule objects were loaded |
| Cloud Environment | Should show `Standard_Salesforce` |

---

## Section 14 — Complete Field Reference

### AI_Pricing_Rule__c

| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Name | `Name` | Text(80) | Rule identifier shown in lists |
| Active | `Active__c` | Checkbox | Must be true for the rule to load |
| Product Code | `Product_Code__c` | Text(255) | Products this rule applies to. `*` = all, blank = all, comma-separated for multiple |
| Rule Category | `Rule_Category__c` | Picklist | `Volume`, `Discount`, `Bundle`, `Custom`, `Override` |
| Priority | `Priority__c` | Number(18,0) | Evaluation order — lower numbers are evaluated first |
| Condition Text | `Condition_Text__c` | Long Text(131072) | **When** this rule applies — the LLM reads this |
| Formula Text | `Formula_Text__c` | Long Text(131072) | **What** the rule calculates — the LLM reads this |
| Effective Date | `Effective_Date__c` | Date | Start of rule validity window |
| Expiry Date | `Expiry_Date__c` | Date | End of rule validity window |

### AI_Product_Rule__c

| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Name | `Name` | Text(80) | |
| Active | `Active__c` | Checkbox | |
| Rule Type | `Rule_Type__c` | Picklist | `Bundle`, `Mandatory`, `Incompatible`, `Recommendation` |
| Primary Product Code | `Primary_Product_Code__c` | Text(255) | Trigger product |
| Related Product Codes | `Related_Product_Codes__c` | Long Text | Comma-separated related products |
| Rule Text | `Rule_Text__c` | Long Text(131072) | Full natural language rule — the LLM reads this |
| Bundle Discount Percent | `Bundle_Discount_Percent__c` | Number(5,2) | Discount % when bundle is detected |
| Priority | `Priority__c` | Number(18,0) | |

### AI_Discount_Rule__c

| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Name | `Name` | Text(80) | |
| Active | `Active__c` | Checkbox | |
| Discount Type | `Discount_Type__c` | Picklist | `Percentage`, `Flat Amount`, `Override` |
| Discount Value | `Discount_Value__c` | Number(5,2) | Default discount the LLM should apply |
| **Max Discount Percent** | `Max_Discount_Percent__c` | Number(5,2) | **Hard ceiling — Apex enforces this. LLM cannot exceed it.** |
| **Approval Required Threshold** | `Approval_Required_Threshold__c` | Number(5,2) | Discount % that triggers approval routing |
| Stackable | `Stackable__c` | Checkbox | Can this discount combine with others |
| Condition Text | `Condition_Text__c` | Long Text | When this discount applies — sent to LLM as context |
| Effective Date | `Effective_Date__c` | Date | |
| Expiry Date | `Expiry_Date__c` | Date | |

### AI_Approval_Policy__c

| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Name | `Name` | Text(80) | |
| Active | `Active__c` | Checkbox | |
| Priority | `Priority__c` | Number(18,0) | First matching policy wins |
| **Min Discount Threshold** | `Min_Discount_Threshold__c` | Number(5,2) | Effective discount % that triggers this policy |
| **Min Deal Value** | `Min_Deal_Value__c` | Currency(16,2) | Net quote total that triggers this policy |
| **Approval Chain** | `Approval_Chain__c` | Text(255) | **Must exactly match the Salesforce Approval Process API name** |
| Trigger Condition | `Trigger_Condition__c` | Long Text | Natural language description — for LLM context |
| Auto Approve Condition | `Auto_Approve_Condition__c` | Long Text | When to bypass approval automatically |

### AI_Delegate_Config__c

| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Name | `Name` | Text(80) | |
| Active | `Active__c` | Checkbox | |
| Primary Approver Role | `Primary_Approver_Role__c` | Text(255) | Role being delegated away from |
| Delegate Approver Role | `Delegate_Approver_Role__c` | Text(255) | Role receiving the delegation |
| Delegation Start | `Delegation_Start__c` | DateTime | When delegation window opens |
| Delegation End | `Delegation_End__c` | DateTime | When delegation window closes |
| Escalation Timeout Hours | `Escalation_Timeout_Hours__c` | Number | Hours before unactioned approvals escalate |

### AI_Engine_Config__c (Hierarchy Custom Setting)

| Field Label | API Name | Type | Purpose |
|---|---|---|---|
| Engine Active | `Engine_Active__c` | Checkbox | Master on/off switch |
| Cloud Environment | `Cloud_Environment__c` | Text(50) | Which adapter to use |
| LLM Model | `LLM_Model__c` | Text(100) | Claude model ID |
| LLM Endpoint URL | `LLM_Endpoint_URL__c` | URL(255) | Optional direct endpoint override |
| Max Quote Lines | `Max_Quote_Lines__c` | Number(18,0) | Sync vs async threshold |
| Enable PII Tokenisation | `Enable_PII_Tokenisation__c` | Checkbox | PII masking before LLM callout |
| Callout Timeout Seconds | `Callout_Timeout_Seconds__c` | Number(18,0) | HTTP timeout |

### AI_Transaction_Log__c (Read-Only Audit Trail)

| Field Label | API Name | Type | What It Shows |
|---|---|---|---|
| Name | `Name` | Auto Number | Log identifier (TXN-00001, TXN-00002...) |
| User Prompt | `User_Prompt__c` | Long Text | Exactly what the user typed |
| Processing Status | `Processing_Status__c` | Picklist | `Pending`, `Success`, `Validation Failed`, `LLM Error`, `Rollback` |
| Quote ID | `Quote_Id__c` | Text(18) | The Quote record created |
| Processing Time Ms | `Processing_Time_Ms__c` | Number | Total time from prompt to quote creation |
| Validation Errors | `Validation_Errors__c` | Long Text | Price corrections or blocks from ValidationEngine |
| Rules Applied | `Rules_Applied__c` | Long Text | Which rule records were loaded |
| Cloud Environment | `Cloud_Environment__c` | Text(50) | Which adapter was used |
| Batch Transaction ID | `Batch_Transaction_Id__c` | Text(255) | Correlation ID for async bulk quotes |
| LLM Response JSON | `LLM_Response_JSON__c` | Long Text | Raw JSON returned by the LLM (for debugging) |

---

## Section 15 — Troubleshooting

| Symptom | Where to Look | Fix |
|---|---|---|
| "AI Engine Disabled" badge on LWC | AI Engine Config custom setting | Set `Engine_Active__c = true` |
| "Could not connect to AQE engine" | AI Engine Config custom setting | Any field is missing or wrong — verify all fields in Section 4 |
| "Backend Unreachable" in wizard | Named Credential + Node.js server | Update URL in Named Credential, ensure server is running, test with `curl /api/health` |
| No rules loaded — LLM ignores rules | AI Pricing Rule records | Check `Active__c = true`, dates are within range, product code matches |
| "Product not found in pricebook" | AI Transaction Log → Validation Errors | Product codes returned by LLM don't match Product2.ProductCode in your org — create the products |
| Quote created but no lines | AI Transaction Log | Validation failed after quote header created — open the log, read `Validation_Errors__c` |
| Discount silently corrected | AI Transaction Log → Validation Errors | `Max_Discount_Percent__c` in AI Discount Rule was breached — Apex corrected it |
| Approval not submitted | AI Approval Policy + Salesforce Approval Process | Ensure `Approval_Chain__c` exactly matches the Approval Process API name in Process Automation |
| Bulk quote stuck in Pending | AI Transaction Log + Apex Jobs | Go to `Setup → Environments → Apex Jobs` — check for failed Queueable jobs |
| 429 error from LLM backend | Node.js server logs | Anthropic rate limit hit — wait or upgrade your Anthropic API tier |
| "Invalid type: AI_Engine_Config__c" | Apex compile error | Custom setting object not deployed — redeploy or reinstall the package |
| Named credential callout fails | Apex debug logs | Check the endpoint URL has no trailing slash, HTTPS is used |

---

## Section 16 — Recommended Test Data Setup

Create these records before testing to ensure the full engine flow works end to end.

### Step 1 — Create Products in Your Org

Go to `App Launcher → Products → New` and create:

```
Product 1:
  Product Name:  Laptop Pro 15
  Product Code:  LAPTOP-PRO-15
  Active:        true

Product 2:
  Product Name:  Extended Warranty
  Product Code:  EXT-WARRANTY
  Active:        true
```

Then go to `App Launcher → Price Books → Standard Price Book → Add Products`:
- Add Laptop Pro 15 at list price `$1,200.00`
- Add Extended Warranty at list price `$150.00`

### Step 2 — Create at Least One AI Pricing Rule

Use the values from the Example 1 in Section 7 (Volume Discount).

### Step 3 — Create at Least One AI Discount Rule

Use the values from Example 1 in Section 9 (Standard Discount Cap, Max 25%).

### Step 4 — Create an Account

`App Launcher → Accounts → New`
- Account Name: `Acme Corporation`
- Type: `Customer`

### Step 5 — Generate Your First Quote

Go to the Acme Corporation Account record, find the AI Quote Generator, type:
```
Create a quote for 100 Laptop Pro 15 units with a 10% volume discount
and include 100 extended warranties for Acme Corporation
```

Expected result:
- Quote header created
- 2 lines: LAPTOP-PRO-15 (qty 100, 10% discount) + EXT-WARRANTY (qty 100)
- Transaction Log entry with status `Success`

---

*Package: AI-Quotation-Engine v1.0.0.1*
*SubscriberPackageVersionId: 04tg50000003jobAAA*
*Dev Hub: amitDevHub (0128amitkumar821@agentforce.com)*
*GitHub: https://github.com/KAKASHII-HATAKE/AI-Quotation-Engine*
