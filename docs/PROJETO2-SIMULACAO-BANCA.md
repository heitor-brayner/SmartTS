# Project 2 — Simulação de banca

## Objetivo

Treinar explicação, raciocínio sob pressão e honestidade técnica. A simulação
não mede memorização de nomes de funções isolados; mede se o integrante conecta
requisito, implementação, teste e limitação.

## Formato recomendado

- 2 integrantes respondendo;
- 1 colega no papel de professor;
- 30 minutos por rodada;
- respostas iniciais de até 90 segundos;
- uma repregunta obrigatória por questão;
- sem consultar código nos primeiros 20 minutos;
- últimos 10 minutos com compartilhamento de tela.

O professor sorteia uma questão de cada bloco. Na rodada seguinte, os
integrantes trocam os temas. Ambos devem dominar todo o projeto.

## Rubrica por resposta

| Nota | Critério |
|---|---|
| 0 | Não responde ou afirma algo tecnicamente falso. |
| 1 | Reconhece o tema, mas não explica mecanismo nem aponta evidência. |
| 2 | Explica corretamente mecanismo e exemplo, com pequena imprecisão. |
| 3 | Explica mecanismo, justificativa, alternativa, teste e limitação. |

Penalidades adicionais:

- `-1`: confundir LLTZ com Michelson final;
- `-1`: atribuir ao grupo uma arquitetura que já veio da `main`;
- `-1`: esconder limitação conhecida;
- `-1`: usar “porque passou no teste” como única justificativa.

Meta individual: pelo menos 24/30 em dez perguntas, sem nenhuma resposta 0.

## Rodada A — Arquitetura

### Cartão A1

**Pergunta:** Compare o pipeline da `main` com o pipeline após o Project 2.

**Repregunta:** O que o grupo preservou em vez de reinventar?

**Elementos para nota 3:** AST parametrizado veio da `main`; novos nós em todas
as fases; checker produz árvore tipada; interpretador modular preservado; LLTZ
estendido.

### Cartão A2

**Pergunta:** Por que pair é estrutural e enum é nominal?

**Repregunta:** Dê um bug que ocorreria se enum fosse estrutural.

**Elementos para nota 3:** igualdade recursiva versus identidade por nome;
separação de domínios; exemplo `Color`/`Status`; referência a `typesEqual`.

### Cartão A3

**Pergunta:** Por que o registro de enums não está em `envBindings`?

**Repregunta:** Qual é o escopo de cada estrutura?

**Elementos para nota 3:** namespace de tipos versus valores; contrato versus
bloco; dois mapas e suas consultas.

## Rodada B — Parser e checker

### Cartão B1

**Pergunta:** Como o parser distingue variável de variante?

**Repregunta:** Qual alternativa de sintaxe removeria a restrição global?

**Elementos para nota 3:** inicial maiúscula; parser não possui registro;
checker confirma; `Enum.Variant` como alternativa.

### Cartão B2

**Pergunta:** Explique o algoritmo de exaustividade.

**Repregunta:** Como vocês tratam case duplicado e desconhecido?

**Elementos para nota 3:** `variants`, `covered`, `missing`, `unknown`, `nub`,
escopo salvo por branch.

### Cartão B3

**Pergunta:** Por que validar enum antes de `Map.fromList`?

**Repregunta:** O que exatamente `Map.fromList` faria com chaves repetidas?

**Elementos para nota 3:** última entrada sobrescreve; significado dependente
de ordem; invariantes de unicidade e cardinalidade.

### Cartão B4

**Pergunta:** Escreva as regras de tipo de pair, `fst` e `snd`.

**Repregunta:** Onde o erro `fst(1)` é detectado?

**Elementos para nota 3:** julgamentos corretos; `inferExpr`; erro estático.

## Rodada C — Runtime e fronteiras

### Cartão C1

**Pergunta:** Como a desestruturação é executada?

**Repregunta:** Por que não gerar duas avaliações independentes?

**Elementos para nota 3:** avalia uma vez; pattern em `PairExpr`; dois bindings;
mutabilidade; risco de efeitos.

### Cartão C2

**Pergunta:** Por que o codec recebe `EnumRegistry`?

**Repregunta:** Por que o parser/type checker não protege automaticamente a
entrada JSON?

**Elementos para nota 3:** JSON não passa pelo parser; `TEnum` só contém nome;
exemplo `Purple`; propagação por `Contract`.

### Cartão C3

**Pergunta:** Por que ainda existe `interpretBug` para match não exaustivo?

**Repregunta:** Isso é erro do usuário ou violação interna?

**Elementos para nota 3:** garantia do checker; defesa interna; árvore tipada
inválida ou bug de pipeline.

## Rodada D — LLTZ e Michelson

### Cartão D1

**Pergunta:** Traduza pair para LLTZ e explique a intenção Michelson.

**Repregunta:** Dê as assinaturas de stack de `PAIR`, `CAR` e `CDR`.

**Elementos para nota 3:** `TTuple`, `TupleExpr`, `Proj`; assinaturas corretas;
topo à esquerda.

### Cartão D2

**Pergunta:** Por que enum usa `TOr` com folhas `TUnit`?

**Repregunta:** O que mudaria se variantes carregassem payload?

**Elementos para nota 3:** soma; alternativa exclusiva; unit para variante
nulária; payload substituiria `TUnit` pelo tipo carregado.

### Cartão D3

**Pergunta:** Desenhe a codificação de três variantes em `or` binário.

**Repregunta:** Como o match seria eliminado?

**Elementos para nota 3:** `or unit (or unit unit)`; injeções corretas;
`IF_LEFT` aninhado; sem `IF_RIGHT`.

### Cartão D4

**Pergunta:** A implementação gera Michelson completo?

**Repregunta:** Liste três lacunas concretas.

**Elementos para nota 3:** termina em LLTZ; sem lowering/contrato completo;
storage/field/call/div/mod; row n-ária ainda abstrata.

## Rodada E — Testes e engenharia

### Cartão E1

**Pergunta:** Por que 117 testes não provam correção total?

**Repregunta:** O que a suíte efetivamente prova?

**Elementos para nota 3:** testes são amostras; cobrem regressões e fronteiras;
não provam lowering inexistente; exemplos de grupos.

### Cartão E2

**Pergunta:** Qual falha real foi descoberta ao compilar com GHC 9.10.3?

**Repregunta:** Como a correção melhorou mais que o warning?

**Elementos para nota 3:** `head` parcial; pattern matching; validação de branch
vazio e igualdade dos tipos.

### Cartão E3

**Pergunta:** Mostre um teste que cruza mais de uma camada.

**Repregunta:** Por que um teste apenas de parser não bastaria?

**Elementos para nota 3:** originate/call; decoder + checker + evaluator;
exemplo de fst/desestruturação/match.

## Sessão prática com código

O professor escolhe uma tarefa:

1. localizar todos os pattern matches afetados por um novo construtor `Expr`;
2. mostrar onde `Red` recebe tipo nominal;
3. mostrar onde um JSON inválido é rejeitado;
4. encontrar onde cases são reordenados;
5. executar `cabal test all --test-show-details=direct`;
6. explicar um teste LLTZ sem apenas ler sua expectativa.

Critério: o integrante deve navegar primeiro para o módulo correto e explicar a
responsabilidade antes de procurar a função.

## Folha de avaliação

| Questão | Integrante | Nota 0–3 | Conceito correto? | Evidência citada? | Limite reconhecido? |
|---|---|---:|---|---|---|
| A__ | | | | | |
| B__ | | | | | |
| C__ | | | | | |
| D__ | | | | | |
| E__ | | | | | |

## Debrief obrigatório

Depois de cada rodada, anotar:

- três conceitos explicados com segurança;
- duas respostas vagas;
- uma afirmação incorreta;
- um arquivo que demorou para localizar;
- um tema para revisar no
  [roteiro completo](PROJETO2-ROTEIRO-ENTREVISTA.md).

