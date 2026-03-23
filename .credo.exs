%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{included: ["lib/", "apps/"], excluded: []},
      checks: [
        {Credo.Check.Refactor.Nesting, [max_nesting: 4]},
        {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 10]},
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Design.TagTODO, false}
      ]
    }
  ]
}
