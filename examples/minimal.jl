using .PocketFlow

# ---- Example Utilities (zero‑dep stub) ----
call_llm(prompt::String) = "LLM says: " * prompt  # swap later with a real backend

# ---- Nodes ----
struct GetQuestionNode <: PocketFlow.AbstractNode end
PocketFlow.exec(::GetQuestionNode, ::Nothing) = "What is PocketFlow?"
PocketFlow.post(::GetQuestionNode, shared, prep_res, question) = (shared.data["question"] = question; "default")

struct AnswerNode <: PocketFlow.AbstractNode end
PocketFlow.prep(::AnswerNode, shared) = get(shared.data, "question", "")
PocketFlow.exec(::AnswerNode, q::String) = call_llm(q)
PocketFlow.post(::AnswerNode, shared, q, ans) = (shared.data["answer"] = ans; nothing) # default

# ---- Wire graph (a >> b) ----
getq = GetQuestionNode()
answer = AnswerNode()
getq >> answer

# ---- Run ----
shared = SharedStore()
flow = Flow(start=getq)
run!(flow, shared)

@info "Q" shared.data["question"]
@info "A" shared.data["answer"]
