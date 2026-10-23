# Invoke in the real guest IEx VM, not in a second OS instance:
# Code.eval_file("/factory/coding/inputs/coding-eval/smoke.exs",
#   evidence_directory: "/priv/eval-smoke-x86_64")
# aarch64 uses the same executable entrypoint with its own evidence directory.
directory = Keyword.fetch!(binding(), :evidence_directory)
{:ok, receipt} = Elixos.CodingEval.Smoke.run!(directory, trusted: true)
IO.inspect(%{result: receipt["result"], identity: receipt["identity"],
  evidence: Path.join(directory, "verified.json")}, label: "actual native three-backend guest Eval")
