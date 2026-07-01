# Project 2 sync notes

Data da sessao: 2026-06-30

Este documento resume o que foi feito para sincronizar a branch do grupo do
Project 2 (`pair<T, U>` and Enum Types) com o `upstream/main` do professor.
O objetivo desta sessao nao foi concluir a implementacao final, mas deixar o
repositorio em um estado limpo para a equipe recomecar a contribuicao final em
cima da arquitetura mais recente.

## Contexto

A branch do grupo continha commits da primeira entrega com suporte inicial a:

- tipo `pair<T, U>`;
- expressoes `pair(e1, e2)`, `fst(e)` e `snd(e)`;
- declaracoes de destructuring `var (a, b): pair<T, U> = ...`;
- declaracoes `enum`;
- literais de enum;
- `match` sobre enums;
- testes e samples para esses recursos.

Depois disso, o `upstream/main` recebeu mudancas grandes do professor:

- remocao de `lib/SmartTS/AST.hs`;
- introducao de `lib/SmartTS/IR/AST.hs`;
- expressoes e statements passaram a ser parametrizados por anotacao:
  `Expr ()`, `Expr Type`, `Stmt ()`, `Stmt Type`;
- o type checker passou a retornar `TypedContract`, em vez de apenas
  `Either String ()`;
- o interpretador foi separado em submodulos:
  `SmartTS.Interpreter.Codec`, `Contract`, `Eval` e `Runtime`;
- foi adicionado um inicio de geracao de codigo LLTZ.

Por causa dessa refatoracao, a implementacao antiga da entrega 1 nao encaixava
diretamente na nova base.

## Conflitos encontrados

O merge com o upstream deixou conflitos em:

- `lib/SmartTS/Parser.hs`;
- `lib/SmartTS/TypeCheck.hs`;
- `samples/Counter.smartts`;
- `test/Main.hs`.

Tambem houve um problema semantico em `lib/SmartTS/Interpreter.hs`: o Git havia
feito merge automatico de trechos antigos da implementacao do grupo em um
arquivo que, no upstream novo, virou apenas um modulo de reexportacao. Isso
deixava dois modulos no mesmo arquivo e referencias a construtores que nao
existiam mais na nova IR.

## Decisao tomada

A decisao foi priorizar uma base limpa e alinhada com o `upstream/main`.

Foram aceitas as versoes do upstream para os arquivos centrais conflitantes:

- `lib/SmartTS/Parser.hs`;
- `lib/SmartTS/TypeCheck.hs`;
- `samples/Counter.smartts`;
- `test/Main.hs`;
- `lib/SmartTS/Interpreter.hs`;
- `smart-ts.cabal`.

Isso significa que a implementacao antiga de `pair` e `enum` foi retirada do
codigo ativo. Ela continua existindo no historico Git dos commits da equipe,
mas nao deve ser continuada diretamente sem port para a nova IR.

Essa foi uma decisao intencional: manter a implementacao antiga misturada com a
nova arquitetura deixaria o repositorio em um estado provavelmente quebrado e
dificil de evoluir.

## Estado final do repositorio

Foi criado um merge commit:

```text
4796304 Merge branch 'main' of https://github.com/rbonifacio/SmartTS
```

Estado apos a resolucao:

- `git status` limpo;
- nenhum arquivo em conflito;
- nenhum marcador `<<<<<<<`, `=======` ou `>>>>>>>`;
- nenhum uso restante, em `app`, `lib` ou `test`, dos construtores antigos:
  `PairExpr`, `TPair`, `TEnum`, `EnumLiteral`, `MatchStmt`,
  `VarDestructStmt`, `ValDestructStmt`, `Fst`, `Snd`;
- a branch local ficou `ahead 7` em relacao a `origin/main`.

O unico delta atual contra `upstream/main` sao os samples antigos da equipe:

- `samples/TrafficLight.smartts`;
- `samples/VotingBox.smartts`.

Esses samples foram preservados como referencia de comportamento desejado, mas
ainda nao sao executaveis na nova base porque usam `pair` e `enum`.

## O que isso implica para a entrega final

A equipe deve tratar a entrega 1 como referencia conceitual, nao como codigo
pronto para continuar.

A implementacao final precisa ser portada para a nova arquitetura, tocando pelo
menos:

- `lib/SmartTS/IR/AST.hs`
  - adicionar `TPair`, `TEnum`, expressoes de pair, enum literal e statement
    de `match`/destructuring;
- `lib/SmartTS/Parser.hs`
  - reimplementar parsing usando os construtores anotados com `()`;
- `lib/SmartTS/TypeCheck.hs`
  - produzir AST tipada com anotacoes `Type`;
  - manter registro nominal de enums;
  - validar exhaustiveness de `match`;
- `lib/SmartTS/Interpreter/Codec.hs`
  - suportar JSON para pair e enum;
- `lib/SmartTS/Interpreter/Eval.hs`
  - avaliar construtor/accessors de pair e literais de enum;
- `lib/SmartTS/Interpreter/Contract.hs`
  - executar destructuring e `match`;
- `lib/SmartTS/CodeGen/CompileLLTZ.hs`
  - decidir e implementar a traducao de `pair` e enum para LLTZ;
- `test/Main.hs`
  - portar/adaptar os testes da entrega 1 para a nova IR anotada;
- `samples/`
  - manter ou ajustar `TrafficLight.smartts` e `VotingBox.smartts`.

## Validacao feita

Foram executadas verificacoes de Git e busca textual:

```text
git status --short --branch
rg -n "<<<<<<<|=======|>>>>>>>" .
rg -n "SmartTS\\.AST|PairExpr|TPair|TEnum|EnumLiteral|MatchStmt|VarDestructStmt|ValDestructStmt|EnumDecl|contractEnums|Fst|Snd" app lib test smart-ts.cabal
git diff --stat upstream/main..HEAD
```

Nao foi possivel rodar `cabal test` porque `cabal`, `stack` e `ghc` nao estavam
disponiveis no PATH da sessao.

## Recomendacao para a equipe

Antes de implementar a feature final, alinhar todos os integrantes neste ponto:

1. Dar pull da branch com o merge commit `4796304`.
2. Confirmar que todos conseguem rodar `cabal test` localmente.
3. Abrir uma branch nova para portar `pair` e `enum` para a nova IR.
4. Usar os commits antigos da equipe como guia de comportamento, mas reescrever
   a implementacao seguindo os modulos novos do upstream.
5. So depois de `parser + typechecker + interpreter` estarem verdes, implementar
   ou ajustar a geracao LLTZ.
