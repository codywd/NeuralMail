# Software Requirements Specification

## NeuralMail

**Version:** 1.0  
**Platform:** macOS (Native)  
**Date:** February 4, 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Architecture](#2-system-architecture)
3. [Functional Requirements](#3-functional-requirements)
4. [Non-Functional Requirements](#4-non-functional-requirements)
5. [Interface Requirements](#5-interface-requirements)
6. [Technical Specifications](#6-technical-specifications)
7. [Risks and Mitigations](#7-risks-and-mitigations)
8. [Appendix: Requirement Tables](#8-appendix-requirement-tables)

---

## 1. Introduction

### 1.1 Purpose

This document defines the requirements for NeuralMail, a native macOS desktop email client that integrates advanced Large Language Model (LLM) capabilities directly into the email workflow. The application is designed to be model-agnostic, supporting both privacy-centric local inference (via LM Studio or similar) and high-performance cloud inference (via OpenAI-compatible APIs).

### 1.2 Scope

NeuralMail functions as a fully-featured email client enhanced by an "Intelligence Layer." This layer intercepts incoming and outgoing data to perform categorization, summarization, sentiment analysis, and generative drafting. The system allows users to "Bring Your Own Key" (BYOK) and configure custom base URLs, ensuring compatibility with any provider adhering to the OpenAI API specification (e.g., LM Studio, Ollama, OpenAI, Anthropic via proxies).

### 1.3 Target Distribution

The application will be distributed as a signed app through the Mac App Store.

### 1.4 Definitions and Acronyms

| Term | Definition |
|------|------------|
| BYOK | Bring Your Own Key - users provide their own API credentials |
| RAG | Retrieval Augmented Generation - using retrieved documents to inform AI responses |
| JMAP | JSON Meta Application Protocol - modern email protocol |
| IMAP | Internet Message Access Protocol |
| SMTP | Simple Mail Transfer Protocol |
| LoRA | Low-Rank Adaptation - a technique for fine-tuning language models |
| DXA | Device-independent units (1440 DXA = 1 inch) |
| SSE | Server-Sent Events |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         NeuralMail Application                       │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │   SwiftUI   │  │  Intelligence│  │    Mail     │  │   Storage  │ │
│  │     UI      │  │    Layer    │  │   Engine    │  │   Layer    │ │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────┬──────┘ │
│         │                │                │                │        │
│         └────────────────┼────────────────┼────────────────┘        │
│                          │                │                          │
│                    ┌─────┴─────┐    ┌─────┴─────┐                   │
│                    │    AI     │    │  Protocol │                   │
│                    │ Provider  │    │  Adapters │                   │
│                    │ Interface │    │           │                   │
│                    └─────┬─────┘    └─────┬─────┘                   │
└──────────────────────────┼────────────────┼─────────────────────────┘
                           │                │
              ┌────────────┴───┐    ┌───────┴────────────┐
              │                │    │                    │
        ┌─────┴─────┐   ┌──────┴────┴──┐   ┌────────────┴────────────┐
        │  Local    │   │    Cloud     │   │    Email Providers      │
        │  (LM      │   │   (OpenAI,   │   │  (Gmail, Outlook,       │
        │  Studio)  │   │   etc.)      │   │   Fastmail, IMAP)       │
        └───────────┘   └──────────────┘   └─────────────────────────┘
```

### 2.2 Hybrid AI Engine

The application relies on a modular "AI Provider" interface supporting both local and cloud inference.

**Local Mode**: Connects to localhost endpoints (e.g., `http://localhost:1234/v1`) for zero-data-egress operations. When Local Mode is active for an AI profile, no email content leaves the device.

**Cloud Mode**: Connects to remote endpoints (e.g., `api.openai.com`) using a user-provided API key. Users must explicitly acknowledge data transmission to external services.

### 2.3 Data Persistence

**Email Data**: Standard local mail storage using SQLite with full-text search capabilities.

**Vector Store**: Local vector database (SQLite with sqlite-vec or embedded LanceDB) to store embeddings for semantic search and RAG functionality.

**Draft Storage**: Drafts stored in the account's IMAP Drafts folder to enable cross-device sync.

**Credentials**: All API keys and OAuth tokens stored in macOS Keychain.

### 2.4 Protocol Support

The application supports multiple email protocols through a unified adapter interface:

| Protocol | Provider | Authentication | Real-Time Sync |
|----------|----------|----------------|----------------|
| IMAP/SMTP | Generic | Username/Password, App Passwords | IDLE on Inbox |
| OAuth + REST | Gmail | OAuth 2.0 with PKCE | Polling via history.list |
| OAuth + REST | Outlook (Personal & M365) | OAuth 2.0 with PKCE | Polling via delta endpoint |
| JMAP | Fastmail | Bearer Token | EventSource (SSE) |

### 2.5 Real-Time Notification Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    MailEventBus                         │
│         (Internal pub/sub for "new mail" events)        │
└─────────────────────────────────────────────────────────┘
                           ▲
          ┌────────────────┼────────────────┐
          │                │                │
┌─────────┴─────┐ ┌────────┴────────┐ ┌─────┴──────┐
│  IMAPWatcher  │ │  GraphPoller    │ │ JMAPPush   │
│  (IDLE+Poll)  │ │  (Delta query)  │ │ (SSE)      │
└───────────────┘ └─────────────────┘ └────────────┘
     IMAP/SMTP        Gmail/Outlook      Fastmail
```

Each provider adapter emits a standardized `MailboxChanged(accountId, folderId, changeType)` event to the bus. The rest of the application subscribes to the bus and remains protocol-agnostic.

**Polling Intervals (User Configurable)**:
- Foreground active: 60 seconds (Gmail/Outlook), real-time (JMAP/IMAP IDLE)
- Foreground idle: 5 minutes
- Background: System-managed (NSBackgroundTask), typically 15-30 minutes
- On battery: Minimum 5 minutes (configurable)
- Manual refresh: Always available

---

## 3. Functional Requirements

### 3.1 Account Management

#### FR-ACCT-01: Unified Account Wizard
The application shall provide a unified "Add Account" wizard that auto-detects the email provider based on the email domain's MX records and routes the user to the appropriate authentication flow.

#### FR-ACCT-02: Multi-Account Support
The application shall support multiple email accounts simultaneously, each with independently configurable AI profiles.

#### FR-ACCT-03: OAuth for Gmail
The application shall implement OAuth 2.0 with PKCE for Gmail accounts, storing refresh tokens securely in macOS Keychain.

#### FR-ACCT-04: OAuth for Microsoft
The application shall implement OAuth 2.0 with PKCE for Microsoft accounts, supporting both personal Microsoft accounts and Microsoft 365 organizational accounts (with admin consent flow support).

#### FR-ACCT-05: JMAP for Fastmail
The application shall support JMAP authentication via bearer token for Fastmail accounts.

#### FR-ACCT-06: Generic IMAP/SMTP
The application shall support standard IMAP/SMTP with username/password or app-specific passwords for generic email providers.

#### FR-ACCT-07: Token Refresh
The application shall handle OAuth token refresh transparently without requiring user intervention.

### 3.2 AI Configuration & Connectivity

#### FR-AI-01: AI Profile Management
The user shall be able to define multiple "AI Profiles" (e.g., "Local - Mistral," "Cloud - GPT-4"). Each profile consists of a name, base URL, API key (if required), and selected model.

#### FR-AI-02: Custom Base URL
The user shall be able to input a custom Base URL for each AI profile, enabling compatibility with any OpenAI-compatible API endpoint.

#### FR-AI-03: BYOK (Bring Your Own Key)
The user shall be able to securely input and store API keys for each AI profile. All keys must be stored in the macOS Keychain.

#### FR-AI-04: Model Selection
The application shall query the `/v1/models` endpoint of the configured provider to populate a dropdown list of available models for the user to select.

#### FR-AI-05: Per-Account AI Assignment
The user shall be able to assign different AI profiles to different email accounts.

#### FR-AI-06: System Prompt Customization
The user shall be able to customize the system prompts used for categorization, summarization, and drafting operations.

### 3.3 Embedding Configuration

#### FR-EMB-01: Embedding Model Configuration
Users shall configure their embedding model endpoint and model name before first use. The application shall not provide a bundled default.

#### FR-EMB-02: Dimension Validation
The application shall store the configured embedding model's vector dimension size and validate consistency on startup.

#### FR-EMB-03: Model Change Warning
Changing the embedding model shall require explicit user confirmation acknowledging that a full re-index of all email content will be required. The user must accept this consequence before the change is applied.

#### FR-EMB-04: Local-First with Remote Fallback
The embedding system shall support both local embedding endpoints (primary) and remote endpoints (fallback), configurable by the user.

### 3.4 Intelligent Triage (Incoming Mail)

#### FR-TRIAGE-01: Auto-Categorization
Upon receipt, emails shall be analyzed and assigned tags based on semantic content using the configured AI model.

#### FR-TRIAGE-02: Fixed Taxonomy
The application shall use a fixed category taxonomy: **Urgent**, **Action Required**, **FYI**, **Waiting On**, **Scheduled**, and **Uncategorized**. All AI models shall be prompted to classify into this fixed set only.

#### FR-TRIAGE-03: Categorization Trigger
Categorization shall run on message arrival by default. Users shall be able to configure this to on-demand only via settings.

#### FR-TRIAGE-04: Manual Override
Users shall be able to manually override AI-assigned categories at any time.

#### FR-TRIAGE-05: Sentiment Analysis
The system shall analyze the tone of incoming emails and display a visual indicator (e.g., colored dot) in the message list view.

#### FR-TRIAGE-06: Thread Summarization
The system shall provide a "TL;DR" summary for email threads, displayed in a dedicated sidebar or preview pane.

#### FR-TRIAGE-07: Incremental Summary Updates
When a new message arrives in a previously-summarized thread, the application shall send the new message plus the existing summary to the AI with instructions to evaluate whether the summary requires a material update. If the AI indicates the summary should change, the application shall store the new summary. Otherwise, it shall append a brief note about the new message to the existing summary.

### 3.5 Assisted Composition (Outgoing Mail)

#### FR-COMPOSE-01: Generative Drafting
The user shall be able to prompt the AI to draft a response based on the thread context. The draft shall appear in the compose window for user review and editing.

#### FR-COMPOSE-02: Tone Adjustment
The user shall have controls to rewrite a draft with specific tones: "More Professional," "More Direct," "Softer," "More Casual," and "More Formal."

#### FR-COMPOSE-03: Style Matching (LoRA Support)
If a user self-identifies that they have loaded a local model with a user-specific LoRA via LM Studio, the system shall utilize it for drafting to mimic user syntax and style.

#### FR-COMPOSE-04: Draft Preservation on Error
If the AI API fails during composition, the application shall display an error notification without discarding any existing draft content.

#### FR-COMPOSE-05: New Message Notification in Compose
When a new message arrives in a thread while the user has a compose window open for that thread, the application shall notify the user with an option to view the new message and optionally update the AI draft based on the new context.

### 3.6 Draft Synchronization

#### FR-DRAFT-01: IMAP Drafts Storage
Drafts shall be stored in the account's IMAP Drafts folder to enable cross-device synchronization.

#### FR-DRAFT-02: AI Metadata Storage
AI-related metadata (model used, tone setting, edit state) shall be stored in custom MIME headers that are stripped when the message is sent.

#### FR-DRAFT-03: Conflict Detection
On opening a draft that was modified on another device, the application shall detect the conflict via timestamp comparison and display a resolution banner.

#### FR-DRAFT-04: Conflict Resolution Options
The conflict resolution banner shall offer three options: "View changes," "Keep this version," and "Use newer version."

### 3.7 Retrieval Augmented Generation (RAG)

#### FR-RAG-01: Semantic Search
The user shall be able to search the inbox using natural language queries (e.g., "What was the deadline for the Vulcan project?").

#### FR-RAG-02: Local Vector Storage
The system shall embed email bodies and store vectors locally to facilitate RAG without sending full mailbox history to a cloud provider.

#### FR-RAG-03: Citation Requirement
Every claim made by the RAG chat feature must link directly to the source email message ID. The interface must display these citations prominently.

#### FR-RAG-04: Background Indexing
Indexing shall run asynchronously during initial sync and ongoing operations without blocking the UI. The application shall remain fully usable during indexing.

### 3.8 Attachment Processing

#### FR-ATT-01: Global Toggle
Attachment text extraction shall be globally toggleable, with the default set to enabled.

#### FR-ATT-02: File Size Limit
Users shall be able to configure a maximum file size for attachment extraction. The default shall be 10MB.

#### FR-ATT-03: Pandoc Extraction
The application shall use Pandoc for text extraction from PDF, DOCX, ODT, RTF, HTML, and Markdown files.

#### FR-ATT-04: Unsupported Format Handling
Unsupported formats (XLSX, password-protected files, scanned PDFs without OCR layer) shall be skipped. The application shall log these skips for user review.

#### FR-ATT-05: Attachment Attribution
Extracted attachment text shall be stored in the same vector index as email bodies, with metadata indicating `source_type: attachment` and the original filename. RAG results shall clearly distinguish between body content and attachment content.

### 3.9 Automation

#### FR-AUTO-01: Action Item Extraction
The system shall parse email text for dates and commitments, offering one-click creation of Apple Reminders or Calendar events.

#### FR-AUTO-02: Apple Integration Only
Calendar and reminder integration shall be limited to native Apple apps (Reminders and Calendar) for version 1.0.

---

## 4. Non-Functional Requirements

### 4.1 Privacy

#### NFR-PRIV-01: Local Mode Isolation
When "Local Mode" is active for an AI profile, no email content shall leave the device. All AI inference requests shall go exclusively to the configured localhost URL.

#### NFR-PRIV-02: No Telemetry
The application shall not transmit telemetry, crash reports, or analytics containing email content under any configuration.

#### NFR-PRIV-03: Log Redaction
Local debug logs, if enabled by the user, shall redact email subjects, bodies, and sender information. By default, logging shall be disabled.

#### NFR-PRIV-04: Ephemeral AI Data
All AI-generated metadata (summaries, categories, sentiment scores) shall be considered ephemeral and non-exportable. This data can be regenerated from source emails at any time.

### 4.2 Performance

#### NFR-PERF-01: UI Responsiveness
The UI thread must remain unblocked during AI inference. All API calls must be asynchronous with appropriate loading indicators.

#### NFR-PERF-02: Background Processing
All AI indexing and analysis operations shall run on background threads without impacting user interaction.

#### NFR-PERF-03: Offline Capability
When both the email server and AI endpoints are unreachable, the application shall operate in a degraded "dumb client" mode. Previously-cached AI analysis (summaries, categories, sentiment) shall remain visible.

### 4.3 Battery Efficiency

#### NFR-BATT-01: Battery-Aware Throttling
The application shall throttle or pause background AI indexing when the MacBook is on battery power. The minimum polling interval on battery shall be 5 minutes (user configurable).

#### NFR-BATT-02: Configurable Behavior
Users shall be able to configure battery behavior, including disabling throttling entirely if desired.

### 4.4 Security

#### NFR-SEC-01: Keychain Storage
All API keys and OAuth tokens must be encrypted at rest via macOS Keychain. The application shall never store credentials in plain text.

#### NFR-SEC-02: Secure Token Handling
OAuth tokens shall be handled according to platform security best practices, including secure storage and transmission only over HTTPS.

### 4.5 Error Handling

#### NFR-ERR-01: Graceful Degradation
AI API failures during background tasks (categorization, indexing) shall be logged locally and retried with exponential backoff. The application shall continue functioning without AI features during outages.

#### NFR-ERR-02: Rate Limit Handling
Rate limit errors (HTTP 429) shall trigger automatic backoff. Pending requests shall be queued and retried according to the provider's rate limit headers.

#### NFR-ERR-03: User Notification
Persistent errors affecting user-initiated operations shall be surfaced via non-blocking notifications with actionable information.

---

## 5. Interface Requirements

### 5.1 Visual Design

#### UI-01: Native macOS Aesthetics
The application shall be built with SwiftUI and follow Apple's Human Interface Guidelines for macOS.

#### UI-02: Mode Indicator
The UI must clearly distinguish between "Local" (Green Shield icon) and "Cloud" (Amber Cloud icon) modes in all views where AI operations occur, particularly the drafting window.

#### UI-03: Sensitive Data Warning
The application shall provide a "Sensitive Data Warning" toggle that requires explicit confirmation before sending any content to non-local AI endpoints.

### 5.2 Settings Panels

#### UI-04: AI Settings Panel
A dedicated "AI Settings" panel shall allow management of:
- AI profiles (endpoints, API keys, model selection)
- Embedding model configuration
- Context window size limits
- System prompts for each AI operation type
- Categorization trigger (on-arrival vs. on-demand)

#### UI-05: Account Settings
Account settings shall allow management of:
- Email account credentials and authentication
- Per-account AI profile assignment
- Sync frequency configuration
- Folder subscriptions (for IMAP IDLE)

#### UI-06: Privacy Settings
Privacy settings shall allow management of:
- Logging preferences
- Battery behavior
- Attachment processing rules
- Vector database retention policy

---

## 6. Technical Specifications

### 6.1 Chunking Strategy for Embeddings

Email content shall be chunked according to the following rules:

| Email Length | Strategy |
|-------------|----------|
| Under 512 tokens | Embed as single document |
| 512-2048 tokens | Chunk by semantic paragraph breaks with 50-100 token overlap |
| Over 2048 tokens | Chunk at 1024 tokens with 128 token overlap |

**Thread Handling**: Each message in a thread shall be embedded separately. Thread ID shall be stored as metadata to enable context retrieval of adjacent messages during RAG operations.

**Metadata Per Chunk**:
- `message_id`: Source email identifier
- `thread_id`: Thread identifier for context retrieval
- `source_type`: "body" or "attachment"
- `filename`: (for attachments) Original filename
- `chunk_index`: Position within the source document

### 6.2 Token Counting

The application shall use a tokenizer compatible with common embedding models (tiktoken's cl100k_base recommended as default). If the configured embedding model provides tokenizer information via API, that shall be used instead.

### 6.3 Threading Implementation

Email threading shall be reconstructed client-side using `In-Reply-To` and `References` headers per RFC 5322. Messages shall be grouped into threads based on header relationships, with fallback to subject-line matching for messages lacking proper headers.

### 6.4 Context Window Management

The application shall implement a token counter utility that:
1. Checks the selected model's context limit (if available via API)
2. Allows user to manually set a "Max Context" cap in settings
3. Implements sliding window summarization for content exceeding the limit

For summarization of long threads exceeding context limits, the application shall use recursive summarization: summarize older messages first, then include those summaries as context for the final summary.

---

## 7. Risks and Mitigations

### 7.1 Context Window Limitations

**Risk**: Users providing a Base URL for a model with a small context window (e.g., 4k tokens) may experience failures when summarizing long threads or analyzing large attachments.

**Mitigation**: 
- Implement token counter utility checking model limits
- Allow user-configurable "Max Context" cap
- Implement recursive summarization for content exceeding limits
- Display clear error messages when context is exceeded

### 7.2 Data Leakage (User Error)

**Risk**: A user might mistakenly think they are using a local model while actually connected to a cloud endpoint, inadvertently sending sensitive data to a third party.

**Mitigation**:
- Clear visual distinction between Local (Green Shield) and Cloud (Amber Cloud) modes
- Sensitive Data Warning toggle requiring explicit confirmation for cloud endpoints
- Prominent mode indicator in the drafting window

### 7.3 API Cost Management

**Risk**: Background processes (auto-categorizing every incoming email) could rack up significant costs if using a paid API like GPT-4.

**Mitigation**:
- Default categorization to on-demand for cloud/paid endpoints
- "On-Demand Only" mode configurable per AI profile
- Cost estimation display in settings (if API provides pricing info)

### 7.4 Model Hallucinations in RAG

**Risk**: The semantic search feature might confidently invent email details that do not exist.

**Mitigation**:
- Mandatory citations linking every claim to source message ID
- Clear UI distinguishing AI-generated summaries from original content
- User-accessible view of retrieved source chunks

### 7.5 Database Bloat

**Risk**: Storing vector embeddings for gigabytes of archived email can consume significant local disk space.

**Mitigation**:
- User-configurable retention policy for Vector DB (e.g., "Only index the last 6 months")
- Use quantization for embeddings where supported
- Display storage usage in settings with cleanup options

### 7.6 Rate Limiting

**Risk**: Neither local nor cloud endpoints handle unlimited requests. Background indexing of a large mailbox could hit rate limits quickly.

**Mitigation**:
- Automatic backoff on 429 errors
- Request queuing with configurable concurrency limits
- Prioritize user-initiated requests over background operations

### 7.7 Embedding Model Consistency

**Risk**: Different embedding models produce different vector dimensions and semantic spaces. Switching models invalidates existing indices.

**Mitigation**:
- Store embedding model identifier with vector database
- Validate model consistency on startup
- Require explicit user acknowledgment before model change triggers full re-index
- Display estimated re-index time before confirmation

---

## 8. Appendix: Requirement Tables

### A1. Authentication Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| AUTH-01 | Support IMAP/SMTP with username/password or app-specific passwords | Must Have |
| AUTH-02 | Implement OAuth 2.0 with PKCE for Gmail, storing tokens in macOS Keychain | Must Have |
| AUTH-03 | Implement OAuth 2.0 with PKCE for Microsoft accounts (personal and M365) | Must Have |
| AUTH-04 | Support JMAP authentication via bearer token for Fastmail | Must Have |
| AUTH-05 | Provide unified "Add Account" wizard with auto-detection based on MX records | Must Have |
| AUTH-06 | Handle OAuth token refresh transparently | Must Have |

### A2. Real-Time Sync Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SYNC-01 | Maintain IMAP IDLE connection on Inbox folder for IMAP accounts | Must Have |
| SYNC-02 | Poll Gmail via history.list API at configurable intervals (default: 60s foreground) | Must Have |
| SYNC-03 | Poll Outlook via delta endpoint at configurable intervals | Must Have |
| SYNC-04 | Use EventSource (SSE) push notifications for JMAP/Fastmail accounts | Must Have |
| SYNC-05 | Emit all provider events to unified MailEventBus | Must Have |
| SYNC-06 | Throttle polling on battery (configurable, default: 5m minimum) | Should Have |

### A3. Embedding and Indexing Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| EMB-01 | Require user to configure embedding model endpoint before first use | Must Have |
| EMB-02 | Store and validate embedding model dimension size on startup | Must Have |
| EMB-03 | Require explicit confirmation and full re-index when changing embedding model | Must Have |
| EMB-04 | Embed emails under 512 tokens as single documents | Must Have |
| EMB-05 | Chunk emails 512-2048 tokens by semantic breaks with 50-100 token overlap | Must Have |
| EMB-06 | Chunk emails over 2048 tokens at 1024 tokens with 128 token overlap | Must Have |
| EMB-07 | Store metadata (message_id, thread_id, source_type, chunk_index) per chunk | Must Have |
| EMB-08 | Run indexing asynchronously without blocking UI | Must Have |

### A4. Attachment Processing Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| ATT-01 | Provide global toggle for attachment extraction (default: on) | Must Have |
| ATT-02 | Allow user-configurable maximum file size (default: 10MB) | Must Have |
| ATT-03 | Use Pandoc for PDF, DOCX, ODT, RTF, HTML, Markdown extraction | Must Have |
| ATT-04 | Skip unsupported formats with logged notification | Must Have |
| ATT-05 | Store attachment text in same vector index with source_type metadata | Must Have |

### A5. Categorization Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| CAT-01 | Use fixed taxonomy: Urgent, Action Required, FYI, Waiting On, Scheduled, Uncategorized | Must Have |
| CAT-02 | Prompt all models to classify into fixed taxonomy only | Must Have |
| CAT-03 | Support configurable trigger: on-arrival (default) or on-demand | Must Have |
| CAT-04 | Allow manual category override | Must Have |

### A6. Summarization Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| SUM-01 | Generate thread summaries on first view | Must Have |
| SUM-02 | Evaluate summary update need when new message arrives in summarized thread | Must Have |
| SUM-03 | Update summary if AI indicates material change; append note otherwise | Must Have |
| SUM-04 | Count evaluation and update as separate API calls | Must Have |

### A7. Draft Sync Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| DRF-01 | Store drafts in account's IMAP Drafts folder | Must Have |
| DRF-02 | Store AI metadata in custom MIME headers, stripped on send | Must Have |
| DRF-03 | Display conflict resolution banner when draft modified on another device | Must Have |
| DRF-04 | Notify user when new message arrives in thread with open compose window | Should Have |

### A8. Error Handling Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| ERR-01 | Display error notification on AI failure without discarding draft content | Must Have |
| ERR-02 | Log and retry background AI failures with exponential backoff | Must Have |
| ERR-03 | Maintain visibility of cached AI metadata in offline/degraded mode | Must Have |
| ERR-04 | Trigger automatic backoff and queue requests on rate limit errors | Must Have |

### A9. Privacy and Security Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| PRV-01 | Make no external AI requests when Local Mode active (localhost only) | Must Have |
| PRV-02 | Never transmit telemetry or analytics containing email content | Must Have |
| PRV-03 | Redact email content from debug logs (logging disabled by default) | Must Have |
| PRV-04 | Treat AI-generated metadata as ephemeral and non-exportable | Must Have |
| SEC-01 | Store all credentials in macOS Keychain (never plain text) | Must Have |
| SEC-02 | Handle OAuth tokens according to platform security best practices | Must Have |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | February 4, 2026 | — | Initial release |

---

*End of Document*
