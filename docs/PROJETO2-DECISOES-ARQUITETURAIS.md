# Project 2 — Decisões arquiteturais em relação à `main`

## Objetivo deste documento

Este guia explica como a implementação do grupo estende a branch `main` para
adicionar `pair<T, U>` e enums. O público principal é um integrante que conhece
programação, mas ainda está formando o modelo mental de compiladores,
interpretadores e linguagens tipadas.

Cada decisão possui duas explicações:

- **Explicação técnica:** descreve tipos, invariantes, estruturas e efeitos no
  pipeline.
- **Explicação didática:** traduz a mesma ideia para uma analogia ou exemplo
  concreto, sem eliminar a precisão.

Também são registradas alternativas, custos e evidências no código. Isso é
importante porque uma boa defesa não consiste apenas em dizer “o código
funciona”, mas em demonstrar por que a solução é coerente com a arquitetura da
`main`.

## 1. Ponto de partida: preservar a arquitetura parametrizada da `main`

### O que existia na `main`

A versão usada como base já havia substituído o AST antigo por uma árvore
parametrizada:

```haskell
Expr a
Stmt a
Contract a
```

O parser produz `Expr ()`, enquanto o type checker produz `Expr Type`. O
interpretador consome a árvore tipada. A `main` também já havia dividido o
interpretador em `Codec`, `Contract`, `Eval` e `Runtime`, e introduzido o IR
LLTZ.

### Decisão

Portar todos os recursos do Project 2 para essa arquitetura, em vez de
reaproveitar literalmente a implementação anterior construída sobre o AST
antigo.

### Explicação técnica

O parâmetro `a` representa a anotação de cada expressão. Na fase sintática, não
há tipo inferido, então `a = ()`. Após a checagem, `a = Type`. Novos
construtores como `PairExpr`, `Fst`, `Snd` e `EnumLiteral` precisam preservar
essa parametrização; caso contrário, o type checker não conseguiria produzir
uma árvore em que cada novo nó carrega seu tipo.

### Explicação didática

Imagine que o AST seja um formulário. O parser preenche os campos de estrutura,
mas deixa a coluna “tipo” em branco. O type checker copia o formulário e
preenche essa coluna. Os novos recursos precisavam entrar no mesmo formulário,
não criar um segundo sistema de papéis incompatível.

### Alternativa rejeitada

Manter tipos separados, como `ParsedExpr` e `TypedExpr`, com árvores distintas.
Isso seria possível, mas divergiria da arquitetura definida pelo professor e
duplicaria todos os construtores.

### Evidência

- [`lib/SmartTS/IR/AST.hs`](../lib/SmartTS/IR/AST.hs)
- [`conflict-resolution.md`](../conflict-resolution.md)

## 2. `pair<T, U>` foi modelado como produto estrutural

### Decisão

Adicionar `TPair Type Type` e `PairExpr`, sem criar nomes ou declarações para
tipos pair.

### Explicação técnica

`TPair t1 t2` é estrutural. A igualdade de tipos é definida recursivamente:

```text
pair<T1,T2> = pair<U1,U2>
se, e somente se, T1 = U1 e T2 = U2
```

Não existe uma identidade nominal associada ao pair. O construtor infere os
dois componentes e produz `TPair (typeOf e1) (typeOf e2)`.

### Explicação didática

Dois pares são do mesmo “formato de caixa” quando o compartimento esquerdo e o
direito guardam os mesmos tipos de objetos. Não importa onde a caixa foi criada
ou qual variável a recebeu.

### Por que essa escolha

É exatamente o objetivo do enunciado: experimentar um tipo parametrizado
composto e estrutural. Também corresponde diretamente ao tipo Michelson
`pair ty1 ty2`.

### Evidência

- `TPair` e `PairExpr` em [`AST.hs`](../lib/SmartTS/IR/AST.hs)
- `typesEqual` e `inferExpr (PairExpr ...)` em
  [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)

## 3. Enums foram modelados como tipos nominais

### Decisão

Representar o uso de um enum por `TEnum Name` e sua declaração por
`EnumDecl { enumName, enumVariants }`.

### Explicação técnica

Para enums, a igualdade de tipos compara o nome declarado:

```text
TEnum "Color" != TEnum "Status"
```

mesmo que ambos possuam duas variantes. Isso impede que valores de domínios
diferentes se tornem intercambiáveis apenas porque suas representações internas
são parecidas.

### Explicação didática

Um semáforo e o estado de uma votação podem ter três opções, mas isso não faz
`Green` virar uma fase da votação. O nome do enum funciona como a identidade de
um documento: dois documentos com o mesmo número de campos continuam sendo
documentos diferentes.

### Alternativa rejeitada

Tratar enums estruturalmente pela lista de variantes. Isso permitiria
compatibilidade acidental entre conceitos de domínio diferentes e contrariaria
o objetivo de aprendizagem sobre tipos nominais.

### Evidência

- `TEnum`, `EnumDecl` e `contractEnums` em
  [`AST.hs`](../lib/SmartTS/IR/AST.hs)
- `typesEqual (TEnum n) (TEnum m)` em
  [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)

## 4. O registro de enums é separado da tabela de símbolos

### Decisão

Adicionar ao ambiente do type checker:

```haskell
envEnumDefs    :: Map Name [Name]
envVariantEnum :: Map Name Name
```

### Explicação técnica

`envBindings` responde “qual é o tipo da variável `x` neste escopo?”. Já
`envEnumDefs` responde “quais variantes definem o tipo nominal `Color`?”. São
namespaces e ciclos de vida diferentes. O mapa inverso `envVariantEnum` permite
inferir `Red : Color` sem procurar linearmente em todas as declarações.

### Explicação didática

A tabela de símbolos é uma lista de pessoas presentes na sala; o registro de
enums é um catálogo de categorias reconhecidas pela escola. Uma pessoa pode
sair da sala ao terminar um bloco, mas a categoria `Color` continua declarada
para todo o contrato.

### Benefício

Além de refletir a semântica nominal, a busca de variante passa a ser direta
no mapa. O custo é manter coerência entre os dois índices.

### Evidência

- `TcEnv` e `buildEnumMaps` em
  [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)

## 5. Variantes são literais não qualificados por convenção de maiúscula

### Decisão

Um identificador sem argumentos iniciado por letra maiúscula é analisado como
`EnumLiteral`; identificadores comuns continuam sendo `Var`.

### Explicação técnica

O parser não possui o registro de tipos durante `parseExpr`. Portanto, ele não
consegue perguntar se `Red` foi declarado em algum enum. A decisão é tomada por
uma regra lexical simples. O type checker posteriormente valida se a variante
existe e determina seu enum nominal.

### Explicação didática

O parser reconhece o uniforme, mas ainda não conhece a identidade da pessoa.
Ao ver um nome com inicial maiúscula, marca “parece uma variante”. O type
checker consulta o cadastro e confirma de qual enum ela faz parte.

### Consequências

- variantes devem começar com maiúscula;
- nomes de variantes precisam ser globais enquanto a sintaxe for `Red`;
- um parâmetro iniciado por maiúscula seria interpretado como variante quando
  referenciado, portanto essa convenção deve ser respeitada pelos autores.

### Alternativa futura

Usar sintaxe qualificada, como `Color.Red`. Isso removeria a necessidade de
unicidade global e permitiria ao parser representar explicitamente o tipo
proprietário.

### Evidência

- `parseVarOrCall` em [`Parser.hs`](../lib/SmartTS/Parser.hs)
- validação de nomes em [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)

## 6. Foram adicionadas invariantes explícitas para declarações enum

### Decisão

Rejeitar nomes de enum duplicados, enum com menos de duas variantes, variantes
duplicadas, colisões globais e variantes iniciadas por minúscula.

### Explicação técnica

Sem validação, `Map.fromList` resolveria duplicatas por sobrescrita silenciosa.
Isso faria o significado do programa depender da ordem de inserção. A
validação ocorre antes da construção dos mapas, garantindo que o registro seja
uma função não ambígua.

O mínimo de duas variantes acompanha o mapeamento direto para uma soma. O tipo
Michelson `or` é binário; enums de zero ou uma alternativa exigiriam
representações especiais (`never`, `unit` ou wrappers), que não fazem parte do
escopo escolhido.

### Explicação didática

Uma agenda não pode ter dois contatos com a mesma chave e esperar que o leitor
adivinhe qual vale. Em vez de deixar o último apagar o primeiro, o compilador
avisa que o cadastro é ambíguo.

### Classificação da decisão

Essas restrições são escolhas do grupo, não texto literal do enunciado. Devem
ser defendidas como invariantes necessárias à sintaxe e representação atuais.

### Evidência

- `validateEnumDecls` em [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)
- testes negativos em [`test/Main.hs`](../test/Main.hs)

## 7. `fst` e `snd` são nós próprios, não chamadas comuns

### Decisão

Reservar `fst` e `snd` e produzir `Fst`/`Snd` no AST, em vez de `Call "fst"`.

### Explicação técnica

Uma chamada comum depende de uma assinatura registrada de método. Projeções
de pair são primitivas polimórficas:

```text
fst :: pair<T,U> -> T
snd :: pair<T,U> -> U
```

Representá-las como nós próprios permite ao type checker extrair diretamente
o componente correto e ao LLTZ gerar `Proj`.

### Explicação didática

`fst` não é uma função escrita pelo usuário. É como o operador `+`: faz parte
das ferramentas básicas da linguagem e possui uma regra de tipo própria.

### Evidência

- palavras reservadas e parsers específicos em
  [`Parser.hs`](../lib/SmartTS/Parser.hs)
- inferência em [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)

## 8. Desestruturação é uma declaração atômica

### Decisão

Criar `VarDestructStmt` e `ValDestructStmt`, mantendo no AST os dois nomes, a
anotação pair e a expressão inicializadora.

### Explicação técnica

A desestruturação introduz dois bindings simultaneamente. O checker garante:

- nomes distintos;
- ausência de colisão no escopo;
- expressão e anotação com o mesmo `TPair`;
- tipo do primeiro binding igual ao componente esquerdo;
- tipo do segundo binding igual ao componente direito;
- mutabilidade coerente com `var` ou `val`.

No interpretador, a expressão é avaliada uma vez e seus dois valores são
inseridos em `rtLocals`.

### Explicação didática

É o ato de abrir uma caixa com dois compartimentos e dar um nome a cada
conteúdo. A caixa é aberta uma única vez; os dois nomes começam a existir no
mesmo ponto do programa.

### Por que não desugar no parser

Transformar imediatamente em duas declarações perderia a informação de que a
origem era uma única operação e poderia avaliar a expressão duas vezes. Manter
um nó explícito facilita checagem, interpretação e mensagens de erro.

### Evidência

- nós em [`AST.hs`](../lib/SmartTS/IR/AST.hs)
- checker em [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)
- execução em [`Eval.hs`](../lib/SmartTS/Interpreter/Eval.hs)

## 9. `match` exige exaustividade em tempo de compilação

### Decisão

O checker compara os cases escritos com a lista completa de variantes do enum
e rejeita cases ausentes, repetidos ou desconhecidos.

### Explicação técnica

Para um discriminante `e : TEnum n`, o algoritmo obtém:

```text
variants = envEnumDefs[n]
covered  = nomes dos cases
missing  = variants - covered
unknown  = covered - variants
```

Cada corpo é verificado em escopo filho com `withSavedEnv`, impedindo que
declarações internas vazem para fora do branch.

### Explicação didática

Se um semáforo pode estar vermelho, verde ou amarelo, o compilador exige que o
programador diga o que fazer nos três estados. Ele não aceita “se aparecer
amarelo, veremos depois”.

### Benefício

Depois do checker, a ausência de case no interpretador representa bug interno,
não erro normal de usuário. Essa é uma garantia estática convertida em uma
pré-condição de runtime.

### Evidência

- `checkStmt (MatchStmt ...)` em
  [`TypeCheck.hs`](../lib/SmartTS/TypeCheck.hs)
- `execStmt (MatchStmt ...)` em
  [`Eval.hs`](../lib/SmartTS/Interpreter/Eval.hs)

## 10. Valores de runtime reutilizam a AST tipada

### Decisão

Representar valores pair e enum com `PairExpr Type ...` e
`EnumLiteral (TEnum n) variant`, em vez de criar uma hierarquia `Value`
separada.

### Explicação técnica

Essa decisão segue o interpretador preexistente, que já usa `TypedExpr` para
valores inteiros, booleanos, unit e records. A extensão mantém o mesmo padrão e
evita conversões entre AST e valor em cada operação.

### Explicação didática

O projeto já usava o mesmo formato tanto para descrever uma constante no
programa quanto para guardar seu resultado avaliado. A implementação adicionou
novos formatos ao mesmo conjunto, em vez de abrir um segundo depósito.

### Custo

Alguns casos impossíveis só são protegidos por disciplina do pipeline e
`interpretBug`, não pelo sistema de tipos de Haskell. Uma arquitetura maior
poderia separar `Expr` e `Value` para tornar estados inválidos
irrepresentáveis.

### Evidência

- [`Eval.hs`](../lib/SmartTS/Interpreter/Eval.hs)
- [`Runtime.hs`](../lib/SmartTS/Interpreter/Runtime.hs)

## 11. O codec JSON passou a receber o registro nominal

### Decisão

Alterar a decodificação para:

```haskell
jsonToExprByType :: EnumRegistry -> Type -> Value -> Either String TypedExpr
```

### Explicação técnica

`TEnum "Color"` contém o nome do tipo, mas não carrega sua lista de variantes.
Sem o registro, qualquer string poderia virar `EnumLiteral`, inclusive
`"Purple"`. O `Contract` agora fornece o registro ao decodificar argumentos e
storage persistido, fazendo a fronteira externa preservar os invariantes do
type checker.

### Explicação didática

Saber que um campo é “do tipo Color” não basta para validar uma palavra se o
validador não tiver a tabela de cores permitidas. O registro é essa tabela.

### Por que isso é importante

Entradas JSON não passam pelo parser de expressões. Se não forem validadas no
codec, podem criar valores que nenhum programa SmartTS válido conseguiria
escrever.

### Evidência

- [`Codec.hs`](../lib/SmartTS/Interpreter/Codec.hs)
- propagação em [`Contract.hs`](../lib/SmartTS/Interpreter/Contract.hs)

## 12. Pair e enum são traduzidos para produtos e somas LLTZ

### Decisão

Usar os construtores de alto nível já existentes no IR:

| SmartTS | LLTZ |
|---|---|
| `pair<T,U>` | `TTuple` |
| `pair(e1,e2)` | `TupleExpr` |
| `fst(e)`/`snd(e)` | `Proj` |
| Enum | `TOr` com folhas `TUnit` rotuladas |
| Variante | `Inj` |
| `match` | `Match` |

### Explicação técnica

Pair é um produto: um valor contém simultaneamente os dois componentes. Enum é
uma soma: um valor ocupa exatamente uma das alternativas. Como as variantes
não carregam payload, cada folha usa `TUnit`; a informação relevante está na
posição/label da injeção.

### Explicação didática

Produto significa “A e B”: o pair guarda os dois. Soma significa “A ou B ou
C”: o enum escolhe apenas uma alternativa. `unit` é usado como envelope vazio,
pois o nome da alternativa já contém toda a informação.

### Correspondência Michelson

```text
PAIR :: ty1 : ty2 : A -> pair ty1 ty2 : A
CAR  :: pair ty1 ty2 : A -> ty1 : A
CDR  :: pair ty1 ty2 : A -> ty2 : A
```

Para enum, `LEFT` e `RIGHT` constroem somas binárias e `IF_LEFT` as elimina.
Não existe instrução Michelson `IF_RIGHT`.

### Evidência

- [`CompileLLTZ.hs`](../lib/SmartTS/CodeGen/CompileLLTZ.hs)
- [Michelson Reference](https://tezos.gitlab.io/michelson-reference/)

## 13. A ordem das variantes é um invariante da tradução

### Decisão

Preservar a ordem de `enumVariants` e reordenar os cases do `match` antes de
construir a row LLTZ.

### Explicação técnica

`Inj` identifica a alternativa por sua posição dentro da row. O `Match` deve
ter branches na mesma ordem. Permitir cases SmartTS em qualquer ordem é uma
conveniência de superfície; o compilador normaliza essa ordem usando o registro
do enum.

### Explicação didática

Se `Red`, `Green`, `Yellow` ocupam as gavetas 0, 1 e 2, respectivamente, os
tratadores também precisam estar alinhados às mesmas gavetas. O usuário pode
listar os casos em outra ordem, mas o compilador os organiza antes de gerar o
IR.

### Evidência

- `translateExpression (EnumLiteral ...)` e
  `translateStatement (MatchStmt ...)` em
  [`CompileLLTZ.hs`](../lib/SmartTS/CodeGen/CompileLLTZ.hs)

## 14. Branches LLTZ precisam produzir o mesmo tipo

### Decisão

Verificar na tradução que todos os corpos do `Match` possuem o mesmo
`exprType`, eliminando o uso parcial de `head` como única fonte do tipo final.

### Explicação técnica

Michelson exige que ambos os lados de `IF_LEFT` transformem a stack na mesma
stack de saída `B`. O `Match` n-ário precisa preservar a mesma propriedade.
Caso contrário, o IR carregaria uma anotação de resultado incompatível com
alguns branches.

### Explicação didática

Uma bifurcação pode seguir caminhos diferentes, mas todos precisam chegar ao
mesmo tipo de destino. Não é válido um caminho retornar número e outro retornar
booleano se o ponto de encontro espera um único formato.

### Evidência

- branch `firstBranch : remainingBranches` em
  [`CompileLLTZ.hs`](../lib/SmartTS/CodeGen/CompileLLTZ.hs)

## 15. Estratégia de testes: validar cada fronteira do pipeline

### Decisão

Organizar testes por parser, checker, codec, interpretador e LLTZ, incluindo
casos positivos e negativos.

### Explicação técnica

Testar apenas parsing provaria somente que a árvore é construída. Os testes
adicionados verificam também:

- inferência e rejeição estática;
- serialização e entradas externas inválidas;
- execução end-to-end por `originate` e `call`;
- estrutura exata dos nós LLTZ;
- ordenação de variantes e branches.

### Explicação didática

É como testar uma linha de produção em cada estação. Uma peça pode entrar com
o formato correto e ainda ser montada ou embalada incorretamente depois.

### Evidência atual

```text
GHC 9.10.3
All 108 tests passed
```

Comando recomendado no PowerShell:

```powershell
$env:GHC_CHARENC = "UTF-8"
cabal test all --test-show-details=direct
```

### Evidência

- [`test/Main.hs`](../test/Main.hs)

## 16. Limites conscientemente mantidos

### Decisão

Não afirmar que a branch gera contratos Michelson completos.

### Explicação técnica

A branch traduz os recursos do Project 2 para LLTZ, mas a infraestrutura base
ainda não possui:

- lowering LLTZ → Michelson;
- tradução de um `TypedContract` completo;
- suporte LLTZ completo para storage, field access, calls, divisão e módulo;
- definição concreta da árvore binária para rows enum n-árias.

### Explicação didática

Foi construída a planta intermediária da obra, não o prédio final. A planta já
expressa corretamente produtos e somas, mas outra etapa ainda precisa
convertê-la nas instruções de máquina Michelson.

### Por que explicitar isso

Reconhecer o limite é sinal de domínio. Chamar LLTZ de “Michelson gerado” seria
uma afirmação tecnicamente incorreta e abriria uma fragilidade durante a
entrevista.

## Resumo das decisões

| Tema | Decisão principal | Garantia obtida |
|---|---|---|
| Arquitetura | Estender `Expr a`/`Stmt a` | Integração com a `main` atual |
| Pair | Tipo estrutural | Igualdade recursiva por componentes |
| Enum | Tipo nominal | Separação de domínios |
| Registro | Separado de bindings | Escopo e identidade corretos |
| Variantes | Maiúsculas e não qualificadas | Parsing simples e determinístico |
| Invariantes | Validação antes de `Map.fromList` | Sem sobrescrita ambígua |
| Desestruturação | Statement explícito | Avaliação única no interpretador |
| Match | Exaustivo estaticamente | Runtime total para valores válidos |
| Codec | Recebe registro enum | Entrada externa validada |
| LLTZ | Produtos e somas | Modelo fiel ao domínio Michelson |
| Testes | Cobertura por estágio | Falhas localizadas e rastreáveis |

