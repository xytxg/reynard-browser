//
//  PromptCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import GeckoView

@MainActor
protocol PromptPresenting {
    func present(_ request: PromptRequest, for session: GeckoSession) async -> PromptResponse?
    func update(_ request: PromptRequest)
    func dismiss(promptID: String)
}

@MainActor
final class PromptCoordinator: PromptDelegate {
    private let presenter: PromptPresenting
    private let onPromptFinished: ((GeckoSession) -> Void)?
    
    init(
        presenter: PromptPresenting,
        onPromptFinished: ((GeckoSession) -> Void)? = nil
    ) {
        self.presenter = presenter
        self.onPromptFinished = onPromptFinished
    }
    
    func onPrompt(session: GeckoSession, request: PromptRequest) async -> PromptResponse? {
        let response = await presenter.present(request, for: session)
        onPromptFinished?(session)
        return response
    }
    
    func onPromptUpdate(session: GeckoSession, request: PromptRequest) {
        presenter.update(request)
    }
    
    func onPromptDismiss(session: GeckoSession, promptId: String) {
        presenter.dismiss(promptID: promptId)
    }
}
