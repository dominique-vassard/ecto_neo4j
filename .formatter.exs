locals_without_parens = [
  outgoing_relationship: 2,
  outgoing_relationship: 3,
  incoming_relationship: 2,
  incoming_relationship: 3
]
# Used by "mix format"
[
  import_deps: [:ecto],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
