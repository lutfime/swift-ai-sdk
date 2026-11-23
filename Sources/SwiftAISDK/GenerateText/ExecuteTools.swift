import Foundation
import AISDKProvider
import AISDKProviderUtils

func executeTools(
    toolCalls: [TypedToolCall],
    tools: ToolSet?,
    tracer: any Tracer,
    telemetry: TelemetrySettings?,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    experimentalContext: JSONValue?
) async throws -> [ToolOutput] {
    guard let tools, !toolCalls.isEmpty else {
        return []
    }

    // SEQUENTIAL (iFaraid, ticket #236 — the lead's ruling): a step's tool
    // calls run ONE AT A TIME in the model's call order, and the results
    // return in that same order. The previous task group ran the calls
    // concurrently and collected them in COMPLETION order, which inverted
    // order-sensitive tools (scratch-world builders: a layer must exist
    // before the heirs declared on it) and handed the model the results
    // shuffled. On error the loop stops immediately — later calls never
    // run (previously they had already started and ran to completion).
    // Scope: the generateText path only; StreamTextActor is untouched.
    // Proven by iFaraid's FaraidAssistant order test (worktree run).
    var outputs: [ToolOutput] = []
    for toolCall in toolCalls {
        if let output = try await executeToolCall(
            toolCall: toolCall,
            tools: tools,
            tracer: tracer,
            telemetry: telemetry,
            messages: messages,
            abortSignal: abortSignal,
            experimentalContext: experimentalContext
        ) {
            outputs.append(output)
        }
    }
    return outputs
}
