# Project 2 — Roteiro de preparação para entrevista

## Como usar este roteiro

Este documento simula perguntas de um professor interessado em verificar
domínio real da implementação. Não memorize frases isoladas. Para cada
pergunta, o integrante deve conseguir:

1. explicar o conceito;
2. apontar onde ele aparece no pipeline;
3. dar um exemplo válido e um inválido;
4. reconhecer os trade-offs e limites da solução.

As respostas abaixo são referências. Uma resposta oral pode ser mais curta,
desde que preserve o raciocínio central.

## Nível 1 — Visão geral do projeto

### 1. O que o grupo adicionou à linguagem?

**Resposta esperada**

Adicionamos um tipo produto estrutural `pair<T,U>`, com construção,
projeções e desestruturação, e enums nominais, com declaração, variantes como
valores, igualdade e `match` exaustivo. As mudanças atravessam AST, parser,
type checker, interpretador, codec JSON, IR LLTZ e testes.

**Explicação didática**

Não foi apenas adicionada sintaxe. Um recurso de linguagem só está completo
quando pode ser lido, representado, validado, executado, serializado e
traduzido para a próxima etapa.

**Possível repregunta**

“Qual dessas etapas foi a mais sensível?” Uma boa resposta destaca o type
checker e o registro nominal, ou a preservação de ordem no LLTZ.

### 2. Qual era a principal diferença entre a implementação antiga e a `main`?

**Resposta esperada**

A `main` passou a usar AST parametrizado (`Expr a`, `Stmt a`, `Contract a`) e
interpretador modular. A implementação precisou ser portada: parser produz
anotação `()`, checker produz `Type`, e as etapas seguintes usam o AST tipado.

**Armadilha**

Não diga que o grupo inventou essa parametrização; ela veio da `main` e foi
respeitada pela nova implementação.

### 3. Por que o recurso precisou tocar tantas partes do projeto?

**Resposta esperada**

Porque cada estágio possui uma responsabilidade distinta. O parser reconhece
sintaxe, o AST preserva estrutura, o checker prova propriedades, o
interpretador define semântica, o codec controla a fronteira JSON e o LLTZ
representa a futura compilação.

## Nível 2 — Pair

### 4. Por que `pair<T,U>` é estrutural?

**Resposta esperada**

Seu tipo é determinado exclusivamente pelos componentes. Dois
`pair<int,bool>` são compatíveis independentemente da variável ou local onde
foram criados. `typesEqual` compara recursivamente os dois lados.

**Exemplo para explicar no quadro**

```text
pair<int,bool> = pair<int,bool>
pair<int,bool> != pair<bool,int>
```

### 5. Qual é a regra de tipo de `pair(e1,e2)`?

**Resposta esperada**

Se `e1 : T` e `e2 : U`, então `pair(e1,e2) : pair<T,U>`. O checker infere os
dois operandos e anota o novo nó com `TPair T U`.

### 6. Qual é a regra de tipo de `fst` e `snd`?

**Resposta esperada**

`fst` exige `pair<T,U>` e produz `T`; `snd` exige o mesmo pair e produz `U`.
Aplicá-los a `int`, por exemplo, é erro estático.

**Repregunta provável**

“Por que não deixar falhar no runtime?” Porque a forma do tipo já é conhecida
estaticamente; adiar o erro reduziria a segurança sem benefício.

### 7. Por que `fst`/`snd` têm nós próprios em vez de `Call`?

**Resposta esperada**

São primitivas polimórficas da linguagem, não métodos SmartTS com assinatura
monomórfica no mapa de funções. Nós próprios permitem regras de tipo e tradução
LLTZ específicas.

### 8. Como a desestruturação mantém a avaliação única?

**Resposta esperada**

No interpretador, `execStmt` avalia a expressão inicializadora uma vez, obtém
`PairExpr v1 v2` e insere os dois bindings. Desugar ingenuamente para duas
projeções poderia avaliar uma expressão com efeitos duas vezes.

**Atenção avançada**

No LLTZ atual, as duas projeções ainda contêm a expressão traduzida em dois
pontos. Isso é seguro para o subconjunto puro hoje traduzível, mas deverá ser
substituído por binding temporário quando calls/efeitos forem suportados.

### 9. Qual a diferença entre `var` e `val` na desestruturação?

**Resposta esperada**

Ambos criam dois bindings com os tipos dos componentes. `var` cria
`LocalMutable`/`Binding True`; `val` cria
`LocalImmutable`/`Binding False`. A diferença é de mutabilidade, não de
extração.

## Nível 3 — Enums e nominalidade

### 10. Por que enum é nominal e pair é estrutural?

**Resposta esperada**

Pair representa composição genérica e é definido pela forma. Enum representa
um conceito declarado do domínio e deve preservar identidade. `Color` e
`Status` não se tornam compatíveis só porque têm o mesmo número de variantes.

### 11. Por que existe um registro separado da tabela de símbolos?

**Resposta esperada**

Bindings locais associam nomes de variáveis a tipos e obedecem escopo de
bloco. Declarações enum associam nomes de tipos a conjuntos ordenados de
variantes e têm escopo de contrato. Misturar os dois impediria representar
corretamente identidade e ciclo de vida.

### 12. Para que servem os dois mapas de enum?

**Resposta esperada**

`envEnumDefs` permite obter a lista ordenada de variantes a partir do nome do
enum, usada em referências, exaustividade e codegen. `envVariantEnum` permite
inferir rapidamente o tipo nominal de um literal a partir da variante.

### 13. Por que variantes precisam ser globalmente únicas?

**Resposta esperada**

Porque a sintaxe atual é não qualificada: escreve-se `Red`, não `Color.Red`.
Se dois enums declarassem `Red`, o literal sozinho seria ambíguo. A validação
rejeita a colisão antes de construir os mapas.

**Alternativa que demonstra maturidade**

Uma futura sintaxe qualificada removeria essa restrição e permitiria variantes
homônimas.

### 14. Por que exigir inicial maiúscula?

**Resposta esperada**

O parser ainda não conhece o registro de enums ao analisar uma expressão. A
capitalização distingue lexicalmente `EnumLiteral` de `Var`. O checker confirma
depois se a variante existe.

### 15. Por que rejeitar enum com menos de duas variantes?

**Resposta esperada**

Foi uma decisão da equipe para manter uma interpretação direta como soma
`TOr`/Michelson `or`, que possui duas alternativas. Enum vazio ou unitário
exigiria definir outra representação, como `never` ou `unit`. Não é uma regra
literal do enunciado, mas uma escolha de escopo que deve ser assumida.

**Armadilha**

Não afirme que toda linguagem ou Michelson proíbe enums unitários. A restrição
é desta implementação.

### 16. O que aconteceria sem validar duplicatas antes de `Map.fromList`?

**Resposta esperada**

O mapa preservaria apenas o último valor para a chave duplicada. O programa
seria aceito com significado dependente da ordem de declaração. Isso é uma
sobrescrita silenciosa e viola a nominalidade.

## Nível 4 — Match e exaustividade

### 17. Como funciona a verificação de exaustividade?

**Resposta esperada**

O checker infere o enum do discriminante, consulta todas as variantes,
compara com os nomes cobertos e calcula ausentes e desconhecidas. Também usa
`nub` para detectar cases repetidos. Qualquer diferença é erro estático.

### 18. Por que cada branch usa `withSavedEnv`?

**Resposta esperada**

Para que bindings declarados dentro de um case não escapem para outros cases
ou para o código posterior. O estado do ambiente é salvo antes do branch e
restaurado depois.

### 19. Por que o interpretador ainda trata ausência de case como erro?

**Resposta esperada**

É uma defesa de consistência. Após type checking, esse estado deveria ser
impossível. Se ocorrer, significa que uma árvore inválida alcançou o
interpretador ou existe um bug no pipeline; por isso é `interpretBug`.

### 20. Cases precisam ser escritos na ordem da declaração?

**Resposta esperada**

Não na superfície SmartTS. O interpretador busca pelo nome. Para LLTZ, a
ordem é posicional, então o compilador reordena os cases de acordo com
`enumVariants`.

### 21. Todos os branches precisam ter o mesmo tipo? Por quê?

**Resposta esperada**

Sim no IR de expressão. O `Match` carrega um único tipo de resultado e a regra
Michelson de `IF_LEFT` exige a mesma stack de saída para ambos os caminhos. A
tradução verifica essa consistência.

## Nível 5 — Interpretador e codec

### 22. Como um valor pair é representado em runtime?

**Resposta esperada**

Como `PairExpr` tipado contendo dois subvalores já avaliados. Isso segue o
modelo preexistente, que reutiliza `TypedExpr` como representação de valores.

### 23. Como um enum é representado em runtime?

**Resposta esperada**

Como `EnumLiteral (TEnum enumName) variant`. O tipo nominal permanece na
anotação e o nome da variante identifica o caso.

### 24. Por que o codec precisa do registro de enums?

**Resposta esperada**

Porque `TEnum name` não contém suas variantes. O decoder precisa consultar
`name -> variants` para impedir que uma string JSON arbitrária produza um
valor inválido.

### 25. Qual seria o erro sem essa validação?

**Resposta esperada**

Uma chamada poderia receber `"Purple"` para `Color { Red, Green }`. Como JSON
não passa pelo parser de expressões, o valor chegaria ao `match` e quebraria a
garantia de exaustividade em runtime.

### 26. Por que pair vira objeto JSON com `fst` e `snd`?

**Resposta esperada**

É uma representação explícita e recursivamente tipável. O decoder sabe qual
tipo aplicar a cada componente. Uma lista de dois elementos também seria
possível, mas perderia nomes e produziria mensagens de erro menos claras.

## Nível 6 — LLTZ e Michelson

### 27. Por que pair vira `TTuple` e enum vira `TOr`?

**Resposta esperada**

Pair é um produto: contém ambos os valores. Enum é uma soma: contém exatamente
uma alternativa. `TTuple` e `TOr` são as representações LLTZ desses conceitos.

### 28. Por que cada variante enum carrega `unit`?

**Resposta esperada**

As variantes não possuem payload. O valor `unit` ocupa a alternativa sem
acrescentar informação; a posição e o label identificam a variante.

### 29. Como `Red`, `Green` e `Blue` poderiam ser representados em Michelson?

**Resposta esperada**

Uma possibilidade de associação à direita é:

```text
or unit (or unit unit)
Red   = Left Unit
Green = Right (Left Unit)
Blue  = Right (Right Unit)
```

O `match` seria implementado com `IF_LEFT` aninhados.

### 30. Existe `IF_RIGHT` em Michelson?

**Resposta esperada**

Não como instrução da referência usada. `LEFT` e `RIGHT` constroem valores de
soma. `IF_LEFT` inspeciona e elimina a soma, executando um dos dois branches.

### 31. Qual é a assinatura de stack de `PAIR`, `CAR` e `CDR`?

**Resposta esperada**

```text
PAIR :: ty1 : ty2 : A -> pair ty1 ty2 : A
CAR  :: pair ty1 ty2 : A -> ty1 : A
CDR  :: pair ty1 ty2 : A -> ty2 : A
```

O tipo mais à esquerda representa o topo da stack.

### 32. A branch gera Michelson completo?

**Resposta esperada**

Não. Ela produz LLTZ para os recursos do Project 2. O repositório não contém
lowering LLTZ → Michelson nem compilação completa de contrato. Também há nós
preexistentes ainda não traduzidos, como storage, field access, calls, divisão
e módulo.

**Armadilha crítica**

Não confundir “modelamos a intenção Michelson” com “geramos e executamos
Michelson final”.

### 33. Por que preservar a ordem das variantes?

**Resposta esperada**

Porque `Inj` e `Match` usam uma row posicional. A alternativa injetada e o
branch correspondente precisam concordar sobre o mesmo índice.

## Nível 7 — Qualidade e testes

### 34. Como vocês sabem que a implementação funciona além do parser?

**Resposta esperada**

A suíte possui testes do checker, codec, execução end-to-end por
originate/call e estrutura LLTZ. São 117 testes passando com GHC 9.10.3.

### 35. Que casos negativos foram testados?

**Resposta esperada**

Mismatch de pair, `fst`/`snd` em não pair, enum não declarado, match não
exaustivo, case desconhecido, enum duplicado, variante duplicada/ambígua,
enum unitário, variante minúscula e string JSON inválida.

### 36. Por que testar a forma exata do LLTZ?

**Resposta esperada**

Porque o programa pode type-checkar e executar no interpretador enquanto o
codegen produz um nó incorreto. Testes estruturais de `TupleExpr`, `Proj`,
`Inj` e `Match` validam a fronteira de compilação.

### 37. Qual warning real levou a uma correção?

**Resposta esperada**

GHC apontou uso parcial de `head` na obtenção do tipo do primeiro branch. A
tradução passou a usar pattern matching e também verifica a consistência dos
tipos restantes. O parser também deixou de usar `head` para verificar
capitalização.

## Exercícios de quadro ou compartilhamento de tela

### Exercício A — rastrear um pair pelo pipeline

Explique `return fst(pair(7, true));`:

1. parser: `Fst () (PairExpr () (CInt () 7) (CBool () True))`;
2. checker: pair recebe `TPair TInt TBool`; `Fst` recebe `TInt`;
3. interpretador: avalia o pair e retorna `CInt TInt 7`;
4. LLTZ: `Proj (TupleExpr ...) (RowPath [0])`;
5. intenção Michelson: construção com `PAIR`, projeção com `CAR`.

### Exercício B — rastrear um match

Para `enum Light { Red, Green }`, explique:

1. parser registra a declaração e cria `MatchStmt`;
2. checker infere `Light`, compara `{Red, Green}` com os cases;
3. interpretador avalia `EnumLiteral` e busca o case pelo nome;
4. LLTZ injeta `unit` na posição da variante;
5. branches são reordenados para a ordem da declaração;
6. intenção Michelson: `or unit unit` e `IF_LEFT`.

### Exercício C — diagnosticar um contrato inválido

```typescript
enum Color { Red, Green }
enum Status { Red, Closed }
```

Resposta: a sintaxe não qualificada torna `Red` ambíguo. A validação rejeita a
colisão global antes de `buildEnumMaps`.

## Respostas que enfraquecem a defesa

- “Fizemos assim porque o teste passou.” — teste é evidência, não justificativa.
- “Enum é igual a inteiro por baixo.” — não nesta implementação; é soma LLTZ.
- “Geramos Michelson.” — a branch termina no LLTZ.
- “`IF_RIGHT` trata o outro caso.” — a instrução relevante é `IF_LEFT`;
  `RIGHT` é construtor.
- “Pair e enum são ambos estruturais.” — enum é nominal.
- “Exaustividade é verificada no runtime.” — é verificada estaticamente; o
  runtime mantém apenas uma defesa interna.
- “O parser sabe quais enums existem.” — o parser usa capitalização; o checker
  consulta o registro.

## Checklist individual antes da entrevista

Cada integrante deve conseguir, sem consultar o código:

- escrever as regras de tipo de pair, `fst` e `snd`;
- explicar estrutural versus nominal;
- justificar os dois mapas de enum;
- descrever o algoritmo de exaustividade;
- explicar por que o codec precisa do registro;
- desenhar a soma binária de um enum com três variantes;
- citar as assinaturas de `PAIR`, `CAR`, `CDR` e `IF_LEFT`;
- distinguir interpretador, LLTZ e Michelson;
- apontar pelo menos duas limitações atuais;
- mencionar um caso negativo coberto por teste em cada estágio.

## Roteiro curto para uma resposta de abertura

> Partimos da `main` já refatorada para um AST parametrizado. Modelamos pair
> como produto estrutural e enum como soma nominal registrada separadamente dos
> bindings. O parser adiciona a sintaxe, o checker infere pares e garante
> exaustividade e invariantes de enum, o interpretador executa construção,
> projeção, desestruturação e match, e o codec valida valores externos contra o
> registro nominal. No LLTZ, pair vira `TTuple`/`Proj` e enum vira
> `TOr`/`Inj`/`Match`. A suíte possui 117 testes passando. A branch não deve ser
> apresentada como backend Michelson completo: ela termina no IR LLTZ.

## Referências para revisão

- [`PROJETO2-DECISOES-ARQUITETURAIS.md`](PROJETO2-DECISOES-ARQUITETURAIS.md)
- [`PROJETO2-ADENDO-TECNICO.md`](PROJETO2-ADENDO-TECNICO.md)
- [`RELATORIO.md`](../RELATORIO.md)
- [`docs/09-projects.md`](09-projects.md)
- [Michelson Reference](https://tezos.gitlab.io/michelson-reference/)

