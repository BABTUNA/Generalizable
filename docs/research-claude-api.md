# Anthropic Messages API client in plain Swift (no SPM) for Generalizable: request shapes for guaranteed-JSON structured output, SSE streaming parser, model IDs, Keychain key storage, AnthropicClient design, error handling and offline fallback

## Summary
The strongest precedent is Anthropic's own Swift code, anthropics/ClaudeForFoundationModels (Apache-2.0, "Copyright 2026 Anthropic PBC"): its ClaudeAPI module is a thin URLSession client for POST /v1/messages with an SSEParser, a StreamEvent enum with forward-compatible .unknown cases, an APIError envelope decoder, a Fallbacks type that encodes `"default"` under the `server-side-fallback-2026-07-01` beta, and a Keychain store (kSecClassGenericPassword + kSecUseDataProtectionKeychain + AfterFirstUnlockThisDeviceOnly with an update-then-add upsert). Its RequestBuilder gets guaranteed JSON via `output_config.format` (type json_schema), not via forced tool use, and strips schema keys the strict validator rejects while forcing `additionalProperties:false` on every object. The two community SDKs (jamesrochabrun/SwiftAnthropic, fumito-ito/AnthropicSwiftSDK) both stream with `URLSession.bytes(for:)` + `.lines`, decode only `data:` lines, wrap the loop in an AsyncThrowingStream whose `onTermination` cancels the Task, and accumulate `input_json_delta.partial_json` into a string that is JSON-parsed at `content_block_stop`/`message_delta`; neither stores the API key (it is an init parameter; SwiftAnthropic's example holds it in `@State`), and neither implements retries. The @Observable pattern to copy is SwiftAnthropic's `MessageDemoObservable` and Apple's mlx-swift-examples `LLMEvaluator`: `@MainActor @Observable` class holding `output`, `isLoading`/`running`, `wasTruncated`, a `Task` handle for cancel, `for try await` appending/assigning text, and an `OutputView` that `.onChange(of: output)` scrolls to bottom and shows a truncation banner. Real-app Keychain precedent for an "anthropic_api_key" is theJayTea/WritingTools `KeychainManager` (actor, service string, account = key name). Retry/backoff has no Swift precedent, so copy the official Python SDK's constants (2 retries, 0.5s initial, 8s max, x0.75-1.0 jitter, honor retry-after-ms/retry-after, retry 408/409/429/5xx and honor x-should-retry). Per the claude-api skill, default model is `claude-opus-5` (thinking adaptive by default; include `fallbacks:"default"`), fast alternative `claude-sonnet-5`, and `claude-fable-5-1` only as an explicit opt-in (it rejects forced tool_choice, so structured output must go through output_config.format there). Offline fallback: protocol-injected provider (AnthropicSwiftSDK's `MessageStreamable`/mock pattern) with two lower tiers, Apple's on-device `SystemLanguageModel` (iOS 26.0+, check `.availability`) and the PRD-mandated bundled authored explanation copy.

## Precedents
- anthropics/ClaudeForFoundationModels (official Anthropic Swift package) — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/SSEParser.swift — Byte-level SSE frame parser: buffers `data:` lines until the blank separator, ignores `event:`/`id:`/`retry:` lines because the payload's `type` discriminates, decodes each frame to StreamEvent, throws when the frame is an `error` event; comment explains why it does not use AsyncSequence.lines (blank separator swallowed -> frames one late when multi-line data is buffered).
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/StreamEvent.swift — StreamEvent enum decoded from the `type` field: message_start, content_block_start(index, block as raw JSON), content_block_delta(index, Delta), content_block_stop, message_delta(stopReason, usage), message_stop, ping, error(APIError), unknown(type). Delta cases text_delta/input_json_delta(partial_json)/thinking_delta/signature_delta/citations_delta/unknown.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/ClaudeClient.swift — Thin client: builds URLRequest to baseURL/v1/messages with content-type, anthropic-version, User-Agent, x-api-key; JSONEncoder .sortedKeys; stream() checks `statusCode >= 400` then drains body and decodes the error envelope before parsing SSE; streamText() yields cumulative text snapshots; check() maps 401/403/404/413/429/529 to APIError.Kind when no JSON envelope; reads `request-id` header.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/HTTPTransport.swift — HTTPTransport protocol (data(for:), bytes(for:)) so tests inject a fake; URLSessionTransport wraps URLSession.bytes(for:) into AsyncThrowingStream<UInt8> with onTermination cancelling the Task; RedirectPolicy delegate refuses cross-origin redirects so x-api-key is never forwarded to another host.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/APIError.swift — APIError Codable struct with Kind enum invalid_request_error/authentication_error/permission_error/not_found_error/request_too_large/rate_limit_error/api_error/overloaded_error/other (forward-compatible), requestID, and APIErrorEnvelope {type:error, error:{...}, request_id}. Same struct decodes HTTP error bodies and SSE `error` events.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/Fallbacks.swift — `fallbacks` encodes either an array of {model, thinking?, output_config?} (beta `server-side-fallback-2026-06-01`) or the scalar "default" (beta `server-side-fallback-2026-07-01`); `requiredBeta` picks the header per form.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/MessagesRequest.swift — MessagesRequest Codable: model, max_tokens (default 16_000), system (String), messages, tools, tool_choice, thinking, temperature/top_p/top_k, cache_control, output_config {format:{type:json_schema, schema}, effort: low|medium|high|xhigh|max}, fallbacks, stream.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeForFoundationModels/RequestBuilder.swift — Guaranteed JSON is produced via `output_config.format` (applyStructuredOutput), not forced tool_choice; comment: forced tool use rejects thinking alongside it, so thinking is dropped when tool_choice == .any; jsonSchema sanitizer keeps only type/properties/required/items/enum/const/anyOf/allOf/oneOf/$ref/$defs/definitions/description/format/additionalProperties and forces additionalProperties:false on every object.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeForFoundationModels/AppAttestStore.swift — KeychainAppAttestStore: kSecClassGenericPassword, kSecAttrService namespace, kSecAttrAccount = "<clientID>#<slot>", kSecUseDataProtectionKeychain:true, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; read via SecItemCopyMatching (errSecItemNotFound -> nil); upsert = SecItemUpdate, on errSecItemNotFound SecItemAdd, on errSecDuplicateItem retry SecItemUpdate; delete tolerates errSecItemNotFound; KeychainError uses SecCopyErrorMessageString.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeForFoundationModels/ErrorMapper.swift — Maps APIError.Kind to product errors: rateLimit/overloaded -> rateLimited (no reset date fabricated), requestTooLarge -> contextSizeExceeded, authentication -> missingCredential (prompt for key), permission/api/invalidRequest/notFound surface as-is; URLError.timedOut -> timeout; Keychain read failures before first unlock handled.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/MessagesResponse.swift — StopReason enum end_turn/max_tokens/stop_sequence/tool_use/refusal/pause_turn/unknown (forward-compatible); Usage fields input_tokens/output_tokens/cache_creation_input_tokens/cache_read_input_tokens.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeAPI/ContentAssembler.swift — Rebuilds streamed content blocks: text/thinking deltas accumulate into the block's field, input_json_delta fragments concatenate into partialInput and are JSON-parsed when the block closes; a text block with no text is dropped (API rejects empty text blocks on replay).
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/README.md — Requires iOS 27 / Xcode 27 (so it cannot be depended on for our iOS 26.5 build); documents auth modes (.apiKey extractable from shipping apps, .proxied, .appAttest), fallbacks: .serverDefault, streaming as cumulative snapshots via session.streamResponse(to:), and error handling via ClaudeError.missingCredential.
- anthropics/ClaudeForFoundationModels — https://github.com/anthropics/ClaudeForFoundationModels/blob/main/Sources/ClaudeForFoundationModels/ClaudeExecutor.swift — Only retry present is a single re-issue after an App Attest token is invalidated, with the comment that retrying a stream is only safe while nothing has been written to the channel yet (a retry would duplicate content). No general backoff/retry exists in any of the three Swift clients.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Sources/Anthropic/Service/AnthropicService.swift — fetchStream(): httpClient.bytes(for:) -> guard statusCode == 200 -> AsyncThrowingStream { Task { for try await line in lines { if line.hasPrefix("data:") decode(line.dropFirst(5)) ; yield } } ; onTermination cancels task }. Non-stream fetch() decodes ErrorResponse on non-200. APIError enum: requestFailed/responseUnsuccessful/invalidData/jsonDecodingFailure/timeOutError.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Sources/Anthropic/Private/Networking/URLSessionHTTPClientAdapter.swift — `let (asyncBytes, urlResponse) = try await urlSession.bytes(for: urlRequest)` then re-yields `asyncBytes.lines` through an AsyncThrowingStream<String>.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Sources/Anthropic/Public/ResponseModels/Message/MessageStreamResponse.swift — One flat Decodable for every SSE payload (type, index, contentBlock, message, delta{type,text,thinking,signature,partialJson,stopReason}, usage, error{type,message}) with StreamEvent raw enum for the six event names.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Sources/Anthropic/Service/DefaultAnthropicService.swift — Service struct holds apiKey, apiVersion "2023-06-01", basePath, betaHeaders; streamMessage sets parameter.stream = true then calls fetchStream; JSONDecoder keyDecodingStrategy .convertFromSnakeCase.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Examples/SwiftAnthropicExample/SwiftAnthropicExample/Messages/MessageDemoObservable.swift — `@MainActor @Observable class` with `message`, `errorMessage`, `isLoading`, a private `Task` handle; streamMessage: `task = Task { isLoading = true; let stream = try await service.streamMessage(p); isLoading = false; for try await result in stream { self.message += result.delta?.text ?? "" } } catch { errorMessage = "\(error)" }`; cancelStream() cancels the task.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Examples/SwiftAnthropicExample/SwiftAnthropicExample/FunctionCalling/MessageFunctionCallingObservable.swift — Streaming tool use: `totalJson += result.delta?.partialJson ?? ""`; tool id/name only arrive in content_block_start (`contentBlock.toolUse`).
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Examples/SwiftAnthropicExample/SwiftAnthropicExample/ApiKeyIntroView.swift — The SDK does NOT persist the key: the example keeps it in `@State private var apiKey` and passes it to AnthropicServiceFactory.service(apiKey:betaHeaders:). Not a storage precedent; confirms Keychain must come from elsewhere.
- jamesrochabrun/SwiftAnthropic — https://github.com/jamesrochabrun/SwiftAnthropic/blob/main/Sources/Anthropic/Public/Parameters/Message/MessageParameter.swift — MessageParameter Encodable: model, maxTokens, system (.text or .list with cache_control), stream, tools [.function(name, description, inputSchema, cacheControl)] encoded with `input_schema`, toolChoice {type: tool|auto|any, name}, thinking.
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Sources/AnthropicSwiftSDK/Network/StreamingParser/AnthropicStreamingParser.swift — Line-state parser over `.lines`: `event:` line sets currentEvent, `data:` line decoded to the typed response for that event (ping/message_start/message_delta/message_stop/content_block_start/delta/stop), `error` event -> continuation.finish(throwing: data.error.type); onTermination cancels Task.
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Sources/AnthropicSwiftSDK/Util/InputJSONDeltaAccumulator.swift — Collects content_block_start(tool_use) + every input_json_delta.partial_json, and at message_delta with stop_reason tool_use joins the fragments and JSONSerialization-parses them into ToolUseContent(id,name,input).
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Sources/AnthropicSwiftSDK/API/Messages.swift — streamMessage: `let (data, response) = try await client.stream(request:)` (URLSession.AsyncBytes) -> guard HTTPURLResponse -> guard statusCode == 200 else throw AnthropicAPIError(fromHttpStatusCode:) -> AnthropicStreamingParser.parse(stream: data.lines).accumulated().
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Sources/AnthropicSwiftSDK/Network/HeaderProvider/AnthropicHeaderProvider.swift — Headers split into AnthropicHeaderProvider (anthropic-version, content-type, anthropic-beta comma-joined) and AuthenticationHeaderProvider (x-api-key).
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Sources/AnthropicSwiftSDK/AnthropicAPIError.swift — AnthropicAPIError raw-string enum of API error types with init(fromHttpStatusCode:) mapping 400/401/403/404/429/500/529.
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Sources/AnthropicSwiftSDK/Entity/SystemPrompt.swift — System prompt encoded as [{type:"text", text, cache_control:{type:"ephemeral"}}] array form (needed for prompt caching).
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Example.swiftpm/Protocol/MessagesSubject.swift — Protocol `MessageStreamable` (streamMessage(...) -> AsyncThrowingStream<StreamingResponse, Error>) injected into the view model so a mock (MockViewModel.swift `MockMessageStreamable`) can replace the network client; this is the seam to reuse for the offline provider.
- fumito-ito/AnthropicSwiftSDK — https://github.com/fumito-ito/AnthropicSwiftSDK/blob/main/Example.swiftpm/ViewModel/StreamViewModel.swift — `@Observable class StreamViewModel` with `errorMessage` didSet toggling `isShowingError`, `isLoading`, `task: Task<Void, Never>?`, `for try await chunk in stream` appending text; StreamView.swift binds `.alert(isPresented: $observable.isShowingError)` and a ProgressView overlay.
- ml-explore/mlx-swift-examples (Apple) — https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/LLMEval/ViewModels/LLMEvaluator.swift — `@Observable @MainActor class LLMEvaluator` with `running`, `output`, `wasTruncated`, `generationTask: Task<Void, Error>?`; streaming loop appends `self.output += chunk` per token on MainActor; sets wasTruncated when token count hits maxTokens.
- ml-explore/mlx-swift-examples (Apple) — https://github.com/ml-explore/mlx-swift-examples/blob/main/Applications/LLMEval/Views/OutputView.swift — ScrollView + ScrollViewReader; Text(output).textSelection(.enabled); `.onChange(of: output) { sp.scrollTo("bottom") }` with a 1x1 Spacer id "bottom"; orange truncation banner when wasTruncated.
- theJayTea/WritingTools (2.4k stars) — https://github.com/theJayTea/WritingTools/blob/main/macOS/WritingTools/App/KeychainManager.swift — Real app storing provider keys (incl. "anthropic_api_key") in Keychain: `actor KeychainManager` singleton, `serviceName` constant, kSecClassGenericPassword with kSecAttrAccount = key name, kSecAttrAccessibleWhenUnlocked, delete-then-SecItemAdd on save, SecItemCopyMatching with kSecReturnData/kSecMatchLimitOne on read, errSecItemNotFound -> nil, nonisolated bootstrap read for app-launch.
- anthropics/anthropic-sdk-python (official) — https://github.com/anthropics/anthropic-sdk-python/blob/main/src/anthropic/_constants.py — DEFAULT_TIMEOUT 10 min (connect 5s), DEFAULT_MAX_RETRIES = 2, INITIAL_RETRY_DELAY = 0.5, MAX_RETRY_DELAY = 8.0.
- anthropics/anthropic-sdk-python (official) — https://github.com/anthropics/anthropic-sdk-python/blob/main/src/anthropic/_base_client.py — _parse_retry_after_header: retry-after-ms (ms) then retry-after (float seconds) then HTTP-date; _calculate_retry_timeout: honor retry-after if > 0 else min(0.5 * 2^n, 8) * (1 - 0.25*random()); _should_retry: obey x-should-retry true/false, else retry 408, 409, 429, >= 500.
- platform.claude.com docs — https://platform.claude.com/docs/en/build-with-claude/streaming.md — Event flow message_start -> (content_block_start, content_block_delta*, content_block_stop)* -> message_delta+ -> message_stop, with ping events anywhere and `event: error` / `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`; delta types text_delta, input_json_delta (partial_json strings, parse after content_block_stop), thinking_delta, signature_delta; usage in message_delta is cumulative; unknown event types must be handled gracefully; error recovery on 4.6+ = resend partial text in a user message asking to continue.
- platform.claude.com docs — https://platform.claude.com/docs/en/build-with-claude/structured-outputs.md — `output_config: {format: {type: "json_schema", schema: {...}}}` returns schema-guaranteed JSON in content[0].text; strict tool use = `strict: true` on the tool with additionalProperties:false + required; GA, no beta header (output_format + structured-outputs-2025-11-13 deprecated); supported on claude-opus-5, claude-sonnet-5, claude-haiku-4-5..., claude-fable-5-1; unsupported: recursive schemas, min/max, minLength/maxLength.
- claude-api skill (bundled) — /private/tmp/claude-501/bundled-skills/2.1.280/fb009d10469adaa1cb32e41de32ba90d/claude-api/SKILL.md and curl/examples.md, shared/tool-use-concepts.md, shared/error-codes.md, shared/model-migration.md (lines 981-995) — Model table (claude-opus-5 $5/$25 1M ctx default; claude-sonnet-5 $2/$10; claude-haiku-4-5 $1/$5 200K; claude-fable-5-1 $10/$50), required headers (x-api-key, anthropic-version: 2023-06-01, content-type), raw SSE example, tool-use JSON shape, `fallbacks: "default"` + `anthropic-beta: server-side-fallback-2026-07-01`, max_tokens guidance (16000 non-streaming, 64000 streaming, lower only for deliberately short output), error code table (429/500/529 retryable), PDF document block shape and limits (32 MB, 600 pages; 100 pages on 200K-context models), forced tool_choice removed on fable-5-1/opus-5-5, temperature/top_p/top_k rejected on Opus 5.
- Apple Developer Documentation (FoundationModels) — https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel and https://developer.apple.com/documentation/foundationmodels/languagemodelsession — SystemLanguageModel and LanguageModelSession are iOS 26.0+; `SystemLanguageModel.default.availability` is .available / .unavailable(.deviceNotEligible | .modelNotReady | other); `streamResponse(to:options:) -> ResponseStream<String>` yields snapshots of partially generated content; `respond(to:options:) async throws -> Response<String>`; init(model:tools:instructions:). Usable as the on-device offline tier in the current iOS 26.5 SDK.
- steipete/CodexBar — https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthCredentials.swift — Opened but NOT applicable: it reads Claude Code's own OAuth credentials from the macOS keychain service "Claude Code-credentials"; not an API-key storage pattern for an iOS app.

## Recommendations
- Build `AnthropicClient` as a plain-Swift struct over `URLSession` modeled on anthropics/ClaudeForFoundationModels `Sources/ClaudeAPI/ClaudeClient.swift`: `Configuration {auth: .apiKey(String)|.none, baseURL: https://api.anthropic.com, version: "2023-06-01"}`, one `urlRequest(for:)` builder that sets `content-type: application/json`, `anthropic-version`, `x-api-key`, optional `anthropic-beta`, uses `JSONEncoder.outputFormatting = .sortedKeys` (stable bytes -> stable prompt-cache prefix), and sets `request.timeoutInterval = 600` to mirror the official SDK's 10-minute default (_constants.py) instead of URLSession's 60 s.
- Get guaranteed JSON with `output_config.format = {type: "json_schema", schema}` exactly as ClaudeForFoundationModels `RequestBuilder.applyStructuredOutput` does (JSON arrives in `content[0].text`); keep the forced-tool-use form (`tools[0].strict = true` + `tool_choice {type:"tool", name}`) only as an alternative because (a) forced tool_choice is a 400 on claude-fable-5-1 / claude-opus-5-5 and (b) RequestBuilder notes the API rejects thinking alongside forced tool use, so you would have to send `thinking: {type: "disabled"}`. Copy RequestBuilder's schema sanitizer: allow only type/properties/required/items/enum/const/anyOf/allOf/oneOf/$ref/$defs/definitions/description/format/additionalProperties and force `additionalProperties: false` on every object.
- Default model `claude-opus-5` (skill rule: never downgrade silently, never append date suffixes); fast alternative `claude-sonnet-5`; `claude-haiku-4-5` only if the user asks for cheapest (200K context, 100-page PDF cap, thinking via budget_tokens). Offer `claude-fable-5-1` as an explicit toggle only, and route its structured() call through output_config.format. Send `fallbacks: "default"` with `anthropic-beta: server-side-fallback-2026-07-01` on Opus 5 by default (ClaudeForFoundationModels `Fallbacks.serverDefault` / `defaultRoutingBetaHeader`), behind a feature flag so a 400 on the beta header can drop it.
- Stream with `URLSession.bytes(for:)` and `.lines` like SwiftAnthropic `AnthropicService.fetchStream` / AnthropicSwiftSDK `Messages.streamMessage`, but check the status first the way `ClaudeClient.stream` does: if `statusCode >= 400`, drain the bytes into a Data body and decode the `APIErrorEnvelope` (`{type:"error", error:{type,message}, request_id}`) before touching SSE. Decode only `data:` lines into a `StreamEvent` enum keyed on the JSON `type` field (ClaudeForFoundationModels `StreamEvent.swift`) with `.unknown(type:)` and `Delta.unknown(type:)` cases so new event/delta types never throw; throw on `type == "error"`.
- Wrap the loop in `AsyncThrowingStream { continuation in let task = Task {...}; continuation.onTermination = { _ in task.cancel() } }` (identical in all three SDKs) so cancelling the SwiftUI `Task` cancels the URLSession request.
- `streamText(system:user:) -> AsyncThrowingStream<String, Error>` should yield cumulative snapshots (accumulated text after each `text_delta`), following `ClaudeClient.streamText` and matching Foundation Models' `ResponseStream` snapshot semantics; the view model then assigns `explanation = snapshot` (idempotent) rather than `+=`.
- `structured(system:user:schema:) -> Data`: non-streaming POST (`stream: false`), `max_tokens: 16000` (ClaudeForFoundationModels default and skill default for non-streaming), then check `stop_reason` before reading content (`MessagesResponse.StopReason` incl. `refusal`, `max_tokens`, `unknown`): throw `.refused` / `.truncated`, else return `Data(content[0].text.utf8)`. For the tool-use variant, take `content[i].tool_use.input` (already an object) and `JSONSerialization.data(withJSONObject:)`; when streaming tool input, concatenate `input_json_delta.partial_json` and parse at `content_block_stop` (AnthropicSwiftSDK `InputJSONDeltaAccumulator`, ClaudeForFoundationModels `ContentAssembler`).
- Store the key in Keychain with a struct copied from ClaudeForFoundationModels `KeychainAppAttestStore`: `kSecClassGenericPassword`, `kSecAttrService = "com.generalizable.anthropic"`, `kSecAttrAccount = "anthropic_api_key"` (account naming from WritingTools `KeychainManager`), `kSecUseDataProtectionKeychain: true`, `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, upsert = `SecItemUpdate` -> on `errSecItemNotFound` `SecItemAdd` -> on `errSecDuplicateItem` retry `SecItemUpdate`; read returns nil on `errSecItemNotFound`; errors via `SecCopyErrorMessageString`. Never put the key in UserDefaults; keep it out of `@AppStorage`. The settings screen holds the key in `@State` only while editing (SwiftAnthropic `ApiKeyIntroView`).
- View model: `@MainActor @Observable final class ExplanationModel` with `explanation: String`, `isStreaming: Bool`, `wasTruncated: Bool`, `errorMessage: String?`, `private var task: Task<Void, Never>?`; `explain()` cancels any prior task then `task = Task { do { isStreaming = true; for try await snapshot in client.streamText(...) { explanation = snapshot } } catch is CancellationError {} catch { errorMessage = ... }; isStreaming = false }` (SwiftAnthropic `MessageDemoObservable`, Apple `LLMEvaluator`). The view uses `ScrollViewReader` + `.onChange(of: explanation) { scrollTo("bottom") }`, `Text(...).textSelection(.enabled)`, a truncation banner when stop_reason == max_tokens (Apple `OutputView`), and `.alert(isPresented:)` bound to the error (AnthropicSwiftSDK `StreamView`).
- Error taxonomy: `enum AnthropicError: Error { case api(APIError) /* kind, message, requestID */; case transport(URLError); case decoding(Error); case refused(category: String?); case truncated(partial: String); case missingCredential; case cancelled }`, with `APIError.Kind` raw-string enum + `.other` (ClaudeForFoundationModels `APIError.swift`). Map like `ErrorMapper`: authentication -> missingCredential (show key entry), rateLimit/overloaded -> retry then fall back, requestTooLarge -> shrink/skip the PDF, permission/invalidRequest -> surface message with request_id.
- Retry policy (no Swift precedent exists in any of the three clients; copy the official Python SDK `_base_client.py`): maxRetries 2; delay = `retry-after-ms`/1000 if present, else `retry-after` seconds if > 0, else `min(0.5 * 2^attempt, 8.0) * (1 - 0.25 * random())`; retry when `x-should-retry: true`, or status 408/409/429/>=500, or URLError timedOut/networkConnectionLost/cannotConnectToHost; never retry when `x-should-retry: false`. Retry a streaming request only if no delta has been yielded yet (ClaudeExecutor comment); after a mid-stream failure on 4.6+ models use the docs' recovery: resend the partial text in a new user message asking the model to continue.
- Offline path: define `protocol ExplanationProvider { func streamText(system:user:) -> AsyncThrowingStream<String, Error>; func structured(system:user:schema:) async throws -> Data }` (AnthropicSwiftSDK's `MessageStreamable` + `MockMessageStreamable` injection seam; ClaudeForFoundationModels `HTTPTransport` seam for tests). Provide three conformers and a `FallbackExplanationProvider` that tries them in order: (1) `AnthropicClient` when a key exists in Keychain; on `URLError.notConnectedToInternet/.networkConnectionLost/.cannotFindHost/.timedOut`, missingCredential, or rateLimit/overloaded after retries -> (2) `OnDeviceProvider` using iOS 26 `FoundationModels` (`guard case .available = SystemLanguageModel.default.availability`; `LanguageModelSession(model: .default, instructions: system)`; `for try await partial in session.streamResponse(to: user)` yielding the snapshot's content -- verify the snapshot accessor name against the iOS 26.5 SDK with the compiler) -> (3) `BundledProvider` that streams the PRD's authored explanation copy for the selected finding (the PRD requires the walkthrough to work offline, so this tier is mandatory regardless of network). Show a small "On-device" / "Offline copy" caption so the demo never looks broken.
- Patient PDF import: send the report as a `document` content block (`{type:"document", source:{type:"base64", media_type:"application/pdf", data}}`) placed before the text block, base64 without newlines, check size < 32 MB and page count (600 pages; 100 on Haiku 4.5) before upload; put the stable tissue-layer glossary in `system` as the array form `[{type:"text", text, cache_control:{type:"ephemeral"}}]` (AnthropicSwiftSDK `SystemPrompt`) so repeated explanations reuse the cache.
- Do not send `temperature`/`top_p`/`top_k` (400 on Opus 5); leave thinking adaptive (omit `thinking`) and control latency with `output_config.effort: "low"` for short patient explanations and `"medium"` for the structured report extraction; set `thinking.display: "summarized"` only if you want to show reasoning.
- Add ClaudeForFoundationModels' `RedirectPolicy` URLSessionTaskDelegate (refuse redirects to a different scheme/host/port) so `x-api-key` is never forwarded off api.anthropic.com; pass it via `session.bytes(for:delegate:)`.

## Concrete values
## 1. Request shapes (POST https://api.anthropic.com/v1/messages)

Headers (all requests):
```
content-type: application/json
x-api-key: <key from Keychain>
anthropic-version: 2023-06-01
anthropic-beta: server-side-fallback-2026-07-01      # only when body has "fallbacks": "default"
```

### 1a. Guaranteed JSON, recommended (output_config.format; what Anthropic's own Swift RequestBuilder does)
```json
{
  "model": "claude-opus-5",
  "max_tokens": 16000,
  "system": [
    {"type": "text",
     "text": "You explain radiology reports to patients in plain words at an 8th-grade reading level. You never diagnose; you say what the report says and what to ask the doctor. Tissue layers available in the viewer: skin, fat, muscle, bone, lungs, organs, blood.",
     "cache_control": {"type": "ephemeral"}}
  ],
  "messages": [
    {"role": "user", "content": [
      {"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": "<base64, no newlines>"}},
      {"type": "text", "text": "Read this radiology report and fill the schema. Use the patient's own report text as evidence."}
    ]}
  ],
  "output_config": {
    "effort": "medium",
    "format": {
      "type": "json_schema",
      "schema": {
        "type": "object",
        "additionalProperties": false,
        "required": ["title", "plain_summary", "findings", "questions_for_doctor"],
        "properties": {
          "title": {"type": "string"},
          "plain_summary": {"type": "string", "description": "2-3 sentences, no jargon"},
          "findings": {
            "type": "array",
            "items": {
              "type": "object",
              "additionalProperties": false,
              "required": ["name", "location", "measurement_mm", "layer", "what_it_means", "urgency"],
              "properties": {
                "name": {"type": "string"},
                "location": {"type": "string"},
                "measurement_mm": {"anyOf": [{"type": "number"}, {"type": "null"}]},
                "layer": {"type": "string", "enum": ["skin", "fat", "muscle", "bone", "lungs", "organs", "blood"]},
                "what_it_means": {"type": "string"},
                "urgency": {"type": "string", "enum": ["routine", "follow_up", "urgent"]}
              }
            }
          },
          "questions_for_doctor": {"type": "array", "items": {"type": "string"}}
        }
      }
    }
  },
  "fallbacks": "default"
}
```
Response: `content[0].type == "text"`, `content[0].text` is schema-valid JSON -> `Data(text.utf8)`. Check `stop_reason` first: `"refusal"` -> output may not match schema; `"max_tokens"` -> incomplete. Schema rules (docs): `additionalProperties:false` on every object, `required` listed, no `minimum/maximum/minLength/maxLength`, no recursion; first use of a new schema pays a one-time compile (24 h cache).

### 1b. Same thing via tool use (works on claude-opus-5 / sonnet-5 / haiku-4-5; 400 on claude-fable-5-1 and claude-opus-5-5)
```json
{
  "model": "claude-opus-5",
  "max_tokens": 16000,
  "system": [{"type": "text", "text": "...same system...", "cache_control": {"type": "ephemeral"}}],
  "messages": [{"role": "user", "content": [ {"type": "document", "...": "..."}, {"type": "text", "text": "Report the findings with the report_findings tool."} ]}],
  "tools": [{
    "name": "report_findings",
    "description": "Record the patient-facing explanation of a radiology report.",
    "strict": true,
    "input_schema": { "...identical schema object as above..." }
  }],
  "tool_choice": {"type": "tool", "name": "report_findings"},
  "thinking": {"type": "disabled"},
  "output_config": {"effort": "medium"}
}
```
Notes: `strict: true` is a top-level tool field (not on tool_choice). Forced `tool_choice` requires thinking off (ClaudeForFoundationModels RequestBuilder: "the API rejects thinking alongside it"); `{type:"disabled"}` is accepted on Opus 5 only at effort high or below. Response: find `content[i].type == "tool_use"`, `input` is already a JSON object -> `JSONSerialization.data(withJSONObject: input)`. `stop_reason` will be `"tool_use"`. Streaming variant: `content_block_start` carries `{type:"tool_use", id, name, input:{}}`; concatenate every `input_json_delta.partial_json`; parse at `content_block_stop`.

### 1c. Streaming plain-language explanation
```json
{
  "model": "claude-opus-5",
  "max_tokens": 8192,
  "stream": true,
  "system": [{"type": "text", "text": "...", "cache_control": {"type": "ephemeral"}}],
  "messages": [{"role": "user", "content": "Explain the finding 'Lung nodule, 14 mm, right upper lobe' to me. Where is it, what layers surround it, what usually happens next?"}],
  "output_config": {"effort": "low"},
  "fallbacks": "default"
}
```
(`max_tokens` 8192 rather than the 64000 streaming default because the output is deliberately short; adaptive thinking tokens count toward it, hence not lower.)

## 2. SSE wire format and Swift parser

Event flow (docs): `message_start` -> repeated [`content_block_start`, `content_block_delta`*, `content_block_stop`] -> `message_delta`+ (cumulative `usage`) -> `message_stop`; `ping` anywhere; `error` anywhere. Delta types: `text_delta{text}`, `input_json_delta{partial_json}`, `thinking_delta{thinking}`, `signature_delta{signature}`, `citations_delta{citation}`. Verbatim samples:
```
event: message_start
data: {"type": "message_start", "message": {"id": "msg_...", "type": "message", "role": "assistant", "content": [], "model": "claude-opus-5", "stop_reason": null, "stop_sequence": null, "usage": {"input_tokens": 25, "output_tokens": 1}}}

event: content_block_start
data: {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}

event: ping
data: {"type": "ping"}

event: content_block_delta
data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"location\":"}}

event: content_block_stop
data: {"type": "content_block_stop", "index": 0}

event: message_delta
data: {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence":null}, "usage": {"output_tokens": 15}}

event: message_stop
data: {"type": "message_stop"}

event: error
data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}
```
HTTP 4xx/5xx bodies are plain JSON, not SSE: `{"type":"error","error":{"type":"not_found_error","message":"..."},"request_id":"req_..."}`; the `request-id` header carries the same id.

Minimal Swift (pattern = SwiftAnthropic `fetchStream` + AnthropicSwiftSDK `Messages.streamMessage` for `.lines`, status check + error envelope + enum from ClaudeForFoundationModels `ClaudeClient`/`StreamEvent`):
```swift
enum StreamEvent: Decodable {
  case messageStart(model: String)
  case contentBlockStart(index: Int, block: [String: Any])   // keep raw; tool_use id/name live here
  case contentBlockDelta(index: Int, delta: Delta)
  case contentBlockStop(index: Int)
  case messageDelta(stopReason: String?, outputTokens: Int)
  case messageStop, ping
  case error(APIError)
  case unknown(type: String)                                   // forward-compat: surface, don't throw
  enum Delta: Decodable {
    case text(String), inputJSON(String), thinking(String), signature(String), unknown(type: String)
    private enum K: String, CodingKey { case type, text, thinking, signature, partialJSON = "partial_json" }
    init(from d: Decoder) throws {
      let c = try d.container(keyedBy: K.self)
      switch try c.decode(String.self, forKey: .type) {
      case "text_delta":       self = .text(try c.decode(String.self, forKey: .text))
      case "input_json_delta": self = .inputJSON(try c.decode(String.self, forKey: .partialJSON))
      case "thinking_delta":   self = .thinking(try c.decode(String.self, forKey: .thinking))
      case "signature_delta":  self = .signature(try c.decode(String.self, forKey: .signature))
      case let t:              self = .unknown(type: t)
      }
    }
  }
  // init(from:) switches on "type": message_start / content_block_start / content_block_delta /
  // content_block_stop / message_delta / message_stop / ping / error / default -> .unknown
}

func events(for request: URLRequest) -> AsyncThrowingStream<StreamEvent, Error> {
  AsyncThrowingStream { continuation in
    let task = Task {
      do {
        let (bytes, response) = try await session.bytes(for: request, delegate: RedirectPolicy(origin: request.url))
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.transport(URLError(.badServerResponse)) }
        if http.statusCode >= 400 {                       // error bodies are JSON, not SSE
          var body = Data(); for try await b in bytes { body.append(b) }
          throw APIError.decode(status: http.statusCode, body: body,
                                requestID: http.value(forHTTPHeaderField: "request-id"))
        }
        let decoder = JSONDecoder()
        for try await line in bytes.lines {               // one `data:` line per event on this API
          guard line.hasPrefix("data:") else { continue } // `event:` lines are redundant: payload.type discriminates
          let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
          guard !json.isEmpty, json != "[DONE]" else { continue }
          let event = try decoder.decode(StreamEvent.self, from: Data(json.utf8))
          if case .error(let apiError) = event { throw apiError }
          continuation.yield(event)
        }
        continuation.finish()
      } catch { continuation.finish(throwing: error) }
    }
    continuation.onTermination = { _ in task.cancel() }
  }
}
```
If you ever need multi-line `data:` frames, switch to the byte-level splitter in ClaudeForFoundationModels `SSEParser.swift` (buffers `data:` lines until the blank line, handles LF/CRLF/CR); `.lines` is fine while every event is a single data line, which is what the API sends today.

## 3. Models and limits (claude-api skill table, cached 2026-06-24)

| Role | Model ID (exact, no date suffix) | Context | $/MTok in/out | Notes |
|---|---|---|---|---|
| Default | `claude-opus-5` | 1M | 5 / 25 | thinking adaptive by default (omit `thinking`), effort default high, forced tool_choice OK, structured outputs GA |
| Fast | `claude-sonnet-5` | 1M | 2 / 10 | same API surface as Opus 5 |
| Cheapest | `claude-haiku-4-5` | 200K | 1 / 5 | thinking only via `{type:"enabled", budget_tokens}`; PDF cap 100 pages; structured outputs supported |
| Most capable (opt-in only) | `claude-fable-5-1` | 1M | 10 / 50 | `tool_choice any/tool` -> 400 (use output_config.format), 30-day retention required, long turns |

`max_tokens`: 16000 for non-streaming `structured()` (ClaudeForFoundationModels default 16_000; skill default); 8192 for the streamed short explanation; up to 64000/128K only with streaming. Per-call cost on Opus 5 for ~3K input + 600 output tokens is about $0.03. Do not send `temperature/top_p/top_k` (400 on Opus 5). Effort: `output_config.effort` = "low" for explanations, "medium" for extraction.

## 4. Keychain store (ClaudeForFoundationModels `KeychainAppAttestStore` + WritingTools naming)
```swift
import Security
struct APIKeyStore {
  static let service = "com.generalizable.anthropic"    // kSecAttrService
  static let account = "anthropic_api_key"              // kSecAttrAccount (WritingTools key name)
  private var query: [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.service,
     kSecAttrAccount: Self.account, kSecUseDataProtectionKeychain: true]
  }
  func read() throws -> String? {
    var q = query; q[kSecReturnData] = true; q[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    switch SecItemCopyMatching(q as CFDictionary, &result) {
    case errSecSuccess: return (result as? Data).map { String(decoding: $0, as: UTF8.self) }
    case errSecItemNotFound: return nil
    case let s: throw KeychainError(status: s)
    }
  }
  func write(_ key: String) throws {                     // upsert: update -> add -> update
    let attrs: [CFString: Any] = [kSecValueData: Data(key.utf8),
                                  kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    switch SecItemUpdate(query as CFDictionary, attrs as CFDictionary) {
    case errSecSuccess: return
    case errSecItemNotFound:
      var add = query; add.merge(attrs) { _, new in new }
      switch SecItemAdd(add as CFDictionary, nil) {
      case errSecSuccess: return
      case errSecDuplicateItem:
        let r = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        guard r == errSecSuccess else { throw KeychainError(status: r) }
      case let s: throw KeychainError(status: s)
      }
    case let s: throw KeychainError(status: s)
    }
  }
  func delete() throws {
    let s = SecItemDelete(query as CFDictionary)
    guard s == errSecSuccess || s == errSecItemNotFound else { throw KeychainError(status: s) }
  }
}
struct KeychainError: LocalizedError { let status: OSStatus
  var errorDescription: String? { "Keychain error: \((SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)")" } }
```
Trim whitespace before saving; empty string -> delete (WritingTools). Never mirror the key into UserDefaults/@AppStorage.

## 5. Client + view-model design (plain Swift, no SPM)

```swift
protocol ExplanationProvider: Sendable {
  func streamText(system: String, user: String) -> AsyncThrowingStream<String, Error>   // cumulative snapshots
  func structured(system: String, user: String, schema: [String: Any]) async throws -> Data
}

struct AnthropicClient: ExplanationProvider {
  struct Configuration { var apiKey: String; var model = "claude-opus-5"; var baseURL = URL(string: "https://api.anthropic.com")!; var version = "2023-06-01"; var useServerFallbacks = true }
  let config: Configuration; let session: URLSession = .shared
  func streamText(system:user:) -> AsyncThrowingStream<String, Error> {
    // body 1c with stream:true; iterate events(for:); acc += text on .contentBlockDelta(_, .text); yield acc;
    // on .messageDelta(stopReason: "max_tokens") throw .truncated(partial: acc); "refusal" -> .refused
  }
  func structured(system:user:schema:) async throws -> Data {
    // body 1a, stream:false, max_tokens 16000; session.data(for:) with retry policy (section 6);
    // check status/envelope; decode MessagesResponse {content, stop_reason}; guard stop_reason not in [refusal, max_tokens];
    // return Data(content.first(where: type == "text").text.utf8)
  }
  private func urlRequest(body: [String: Any], stream: Bool) throws -> URLRequest {
    var r = URLRequest(url: config.baseURL.appending(path: "v1/messages")); r.httpMethod = "POST"; r.timeoutInterval = 600
    r.setValue("application/json", forHTTPHeaderField: "content-type")
    r.setValue(config.version, forHTTPHeaderField: "anthropic-version")
    r.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
    if config.useServerFallbacks { r.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
    r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    return r
  }
}

@MainActor @Observable final class ExplanationModel {
  var explanation = ""; var isStreaming = false; var wasTruncated = false; var errorMessage: String?
  var provider: ExplanationProvider   // FallbackExplanationProvider([anthropic, onDevice, bundled])
  private var task: Task<Void, Never>?
  func explain(finding: Finding) {
    task?.cancel(); explanation = ""; wasTruncated = false; errorMessage = nil
    task = Task {
      isStreaming = true; defer { isStreaming = false }
      do { for try await snapshot in provider.streamText(system: Prompts.patientSystem, user: finding.prompt) { explanation = snapshot } }
      catch is CancellationError {}
      catch AnthropicError.truncated(let partial) { explanation = partial; wasTruncated = true }
      catch { errorMessage = error.localizedDescription }
    }
  }
  func cancel() { task?.cancel() }
}
```
Files: `App/AI/AnthropicClient.swift`, `App/AI/StreamEvent.swift`, `App/AI/APIError.swift`, `App/AI/APIKeyStore.swift`, `App/AI/RetryPolicy.swift`, `App/AI/ExplanationProvider.swift` (+ OnDeviceProvider, BundledProvider, FallbackExplanationProvider), `App/AI/ExplanationModel.swift`.

## 6. Errors, retry, offline

APIError kinds (raw strings): invalid_request_error(400) authentication_error(401) billing_error(402) permission_error(403) not_found_error(404) request_too_large(413) rate_limit_error(429, retry) api_error(500, retry) overloaded_error(529, retry) + `other`. Stop reasons: end_turn, max_tokens, stop_sequence, tool_use, refusal (+ `stop_details.category`), pause_turn, unknown.

Retry (official Python SDK): `maxRetries = 2`, `initial = 0.5 s`, `max = 8 s`;
`delay = retry-after-ms/1000 ?? retry-after(seconds) if > 0 ?? min(0.5 * 2^attempt, 8) * (1 - 0.25 * random01)`;
retry if `x-should-retry == "true"`, else 408/409/429/>=500 or URLError(.timedOut/.networkConnectionLost/.cannotConnectToHost); never if `x-should-retry == "false"`. For streams retry only before the first yielded snapshot; otherwise resend `"Your previous response was interrupted and ended with [partial]. Continue from where you left off."` as a new user message (docs, 4.6+ models).

Offline decision order (FallbackExplanationProvider): key in Keychain AND no URLError(.notConnectedToInternet/.networkConnectionLost/.cannotFindHost/.dataNotAllowed) -> AnthropicClient; else if `SystemLanguageModel.default.availability == .available` (iOS 26.0+ FoundationModels; `LanguageModelSession(model: .default, instructions: system)`, `streamResponse(to:)` yields snapshots) -> OnDeviceProvider; else BundledProvider streams `finding.authoredExplanation` in ~40-char chunks with `Task.sleep(for: .milliseconds(30))` so the UI path is identical. Caption the source ("Claude", "On-device", "Offline copy"). No precedent was opened for NWPathMonitor-based detection; the error-driven fallback above is what the cited code does.

PDF input limits: request <= 32 MB, <= 600 pages (100 on 200K-context models), base64 must not contain newlines, document block before the text block.

## Risks
- A bundled/entered API key is extractable from a shipping app (ClaudeForFoundationModels README, AuthMode.apiKey doc comment); Keychain only protects it at rest on the device. Fine for the hackathon demo; for anything public, route through a proxy that adds the key server-side (AuthMode.proxied) or App Attest.
- Forced `tool_choice` (`any`/`tool`) returns 400 on claude-fable-5-1 and claude-opus-5-5, and requires thinking disabled on Opus 5 (which is itself rejected at effort xhigh/max and can cause tool calls to leak into visible text). Prefer output_config.format; keep the tool-use variant behind the model check.
- `anthropic-beta: server-side-fallback-2026-07-01` returns 400 'Unexpected value(s)' if the org is not enabled; ship `fallbacks` behind a flag and drop both header and field on that error.
- Medical content can trip safety classifiers on Opus 5 / Fable 5.1 (`stop_reason: refusal`, category e.g. bio); with structured outputs the refusal output may not match the schema. Always branch on stop_reason before parsing; fallbacks: default mitigates but can still refuse.
- Truncation: adaptive-thinking tokens count against max_tokens; a too-small max_tokens yields stop_reason max_tokens and, for tool input, a partial JSON that parses as a valid-looking partial object. Check stop_reason == max_tokens before trusting tool input; show the truncation banner.
- `.lines`-based parsing assumes one `data:` line per event; a multi-line data frame would be decoded per-line and fail. Anthropic's own SSEParser splits bytes and buffers until the blank line for this reason; switch if the API ever emits multi-line data.
- URLSession's default 60 s timeoutInterval can kill a non-streaming 16000-token structured call; set timeoutInterval to 600 s (SDK default) or stream the structured call and reassemble.
- Structured-output schema rejects minimum/maximum/minLength/maxLength/recursion and needs additionalProperties:false on every object; a stray key is a hard 400. First request with a new schema is slower (compile), cached 24 h.
- Prompt-cache minimum prefix is model-dependent (512-4096 tokens); a short system prompt will silently not cache. Harmless, but do not expect cache_read_input_tokens > 0 for tiny prompts.
- On-device FoundationModels tier requires an Apple Intelligence-eligible device with the model downloaded; on the simulator it depends on the macOS 26 host. The bundled authored copy must exist for every finding (PRD acceptance: offline walkthrough), so treat on-device as a bonus tier, not the floor. The `ResponseStream` snapshot accessor name should be confirmed against the iOS 26.5 SDK with a compile.
- PDF page/size limits (600 pages, 100 on Haiku 4.5, 32 MB) and base64 newlines will cause 400/413; validate before upload and never truncate silently (skill pitfall) -- tell the user and offer page ranges.
- claude-fable-5-1 requires 30-day data retention and costs 2x Opus 5; long turns can take minutes, so if offered as a toggle, warn in UI and keep streaming on.
- Retrying a streaming request after tokens were shown duplicates content (ClaudeExecutor comment); only retry pre-first-token, otherwise use the continuation prompt.
- Model IDs in the skill are cached (2026-06-24); if a 404 `model: ...` appears, query GET /v1/models rather than guessing a new ID.
