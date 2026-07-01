# Project 2 — Adendo técnico da implementação

Este documento complementa, sem substituir, o material upstream em
`README.md` e `docs/01`–`docs/09`. Esses documentos descrevem a linguagem-base
usada como ponto inicial do trabalho. Aqui estão registradas apenas as
extensões e decisões da implementação de `pair<T, U>` e enums desta branch.

Quando houver divergência entre este documento e planos históricos em
`docs/superpowers/`, este documento e o código testado representam o estado
atual da implementação.

## 1. Escopo atendido

O Project 2 de `docs/09-projects.md` pede:

- um tipo produto estrutural `pair<T, U>`;
- construção com `pair(e1, e2)`;
- projeções `fst(e)` e `snd(e)`;
- declarações por desestruturação;
- enums nominais com variantes usadas como valores;
- igualdade entre valores enum;
- dispatch por `match`;
- verificação estática de exaustividade;
- suporte no parser, AST, type checker, interpretador, testes e geração LLTZ.

Todos esses itens estão implementados e cobertos pela suíte. A geração termina
no IR LLTZ: este repositório não contém um backend LLTZ → Michelson nem uma
função de compilação de contrato completo.

## 2. Sintaxe SmartTS

```typescript
enum Light { Red, Green, Yellow }

val p: pair<int, bool> = pair(7, true);
val first: int = fst(p);
val second: bool = snd(p);
val (x, enabled): pair<int, bool> = p;

match (light) {
  Red => { /* ... */ }
  Green => { /* ... */ }
  Yellow => { /* ... */ }
}
```

Enums são declarados entre o bloco de storage e os métodos. Variantes são
identificadores iniciados por letra maiúscula. Como os literais são escritos
sem qualificação (`Red`, e não `Light.Red`), seus nomes devem ser globalmente
únicos dentro do contrato.

## 3. Representação no AST

| Conceito | Representação |
|---|---|
| Tipo par | `TPair Type Type` |
| Tipo enum | `TEnum Name` |
| Declaração enum | `EnumDecl { enumName, enumVariants }` |
| Construção de par | `PairExpr` |
| Projeções | `Fst`, `Snd` |
| Variante enum | `EnumLiteral` |
| Match | `MatchStmt` |
| Desestruturação | `VarDestructStmt`, `ValDestructStmt` |

`TPair` é estrutural: `pair<int, bool>` é igual a outro par com os mesmos
tipos componentes. `TEnum` é nominal: enums diferentes continuam sendo tipos
diferentes mesmo quando possuem a mesma quantidade de variantes.

O parser produz `Contract ()` e o type checker reconstrói `Contract Type`,
anotando cada expressão com seu tipo inferido. Essa arquitetura já é parte da
`main` atual, embora alguns documentos upstream ainda mostrem o AST antigo não
parametrizado.

## 4. Regras de tipo e invariantes

As regras centrais são:

```text
e1 : T    e2 : U
-----------------------
pair(e1, e2) : pair<T,U>

e : pair<T,U>             e : pair<T,U>
---------------           ---------------
fst(e) : T                snd(e) : U
```

Para enums, o ambiente mantém dois registros separados da tabela de símbolos:

```text
enum name -> variantes ordenadas
variante  -> enum nominal
```

O type checker rejeita:

- enums com nomes duplicados;
- enums com menos de duas variantes;
- variantes duplicadas no mesmo enum;
- variantes compartilhadas por enums diferentes;
- variantes iniciadas por minúscula;
- referências a enums não declarados;
- `fst`/`snd` sobre valores não pair;
- desestruturação com tipo ou nomes inválidos;
- `match` sobre valor não enum;
- cases ausentes, duplicados ou desconhecidos.

O mínimo de duas variantes acompanha a representação escolhida em `TOr` e o
fato de o tipo Michelson `or ty1 ty2` ser binário. Outra política seria
possível, mas exigiria definir representações específicas para enum vazio e
enum unitário.

## 5. Semântica do interpretador e codec

O interpretador representa valores pair com `PairExpr` já avaliado. `Fst` e
`Snd` avaliam o operando e selecionam um componente. A desestruturação avalia
o par uma vez e cria dois bindings, mutáveis para `var` e imutáveis para
`val`.

`MatchStmt` avalia o discriminante e executa o case associado ao nome da
variante. A ausência de case é tratada como erro interno porque um contrato
aceito pelo type checker deve ser exaustivo.

No JSON:

```json
{"fst": 7, "snd": true}
```

representa um pair, enquanto uma variante enum é representada como string. A
decodificação recebe o registro nominal do contrato:

```haskell
jsonToExprByType :: EnumRegistry -> Type -> Value -> Either String TypedExpr
```

Assim, uma entrada externa como `"Purple"` é rejeitada quando `Purple` não
pertence ao enum esperado, antes de chegar ao interpretador.

## 6. Correspondência LLTZ e Michelson

| SmartTS | LLTZ atual | Intenção Michelson |
|---|---|---|
| `pair<T,U>` | `TTuple` com duas folhas | `pair T U` |
| `pair(e1,e2)` | `TupleExpr` | `PAIR` |
| `fst(e)` | `Proj e [0]` | `CAR` |
| `snd(e)` | `Proj e [1]` | `CDR` |
| Enum | `TOr` de folhas `unit` rotuladas | árvore binária de `or` |
| Variante | `Inj` com payload `unit` | `LEFT`/`RIGHT` aninhados |
| `match` | `Match` com branches ordenados | `IF_LEFT` aninhados |

As assinaturas formais relevantes da Michelson Reference são:

```text
PAIR    :: ty1 : ty2 : A -> pair ty1 ty2 : A
CAR     :: pair ty1 ty2 : A -> ty1 : A
CDR     :: pair ty1 ty2 : A -> ty2 : A
LEFT    :: ty1 : A -> or ty1 ty2 : A
RIGHT   :: ty2 : A -> or ty1 ty2 : A
IF_LEFT :: or ty1 ty2 : A -> B
```

Em `IF_LEFT`, ambos os branches devem produzir a mesma stack de saída `B`.
Por isso a tradução LLTZ verifica que todos os corpos do `Match` possuem o
mesmo tipo de resultado. A ordem dos cases SmartTS é normalizada para a ordem
da declaração do enum antes de construir a row LLTZ.

Referência oficial: <https://tezos.gitlab.io/michelson-reference/>.

Não existe instrução Michelson `IF_RIGHT`. `LEFT` e `RIGHT` são construtores;
`IF_LEFT` é o eliminador do tipo soma.

## 7. Validação automatizada

Ambiente verificado:

```text
GHC 9.10.3
cabal-install 3.16.1.0
```

Comando no PowerShell:

```powershell
$env:GHC_CHARENC = "UTF-8"
cabal test all --test-show-details=direct
```

Resultado atual:

```text
All 108 tests passed
Test suite smart-ts-test: PASS
```

A suíte cobre parser, type checker, codec JSON, execução end-to-end do
interpretador e construção de tipos/expressões LLTZ. Entre os casos específicos
estão projeção, desestruturação, igualdade estrutural de pair, igualdade nominal
de enum, dispatch do match, `Inj`, `Proj`, `TupleExpr` e ordenação dos branches.

## 8. Limitações conhecidas

- Não há backend LLTZ → Michelson neste repositório.
- Não há uma função que traduza um `TypedContract` inteiro para código final.
- A infraestrutura LLTZ preexistente ainda deixa `StorageExpr`, `FieldAccess`,
  chamadas, atribuições de storage/campo, divisão e módulo como casos não
  implementados.
- A codificação binária concreta de uma row enum com três ou mais variantes
  deve ser definida pelo futuro lowering Michelson.
- Literais enum não qualificados exigem unicidade global de variantes. Uma
  futura sintaxe `Enum.Variant` permitiria remover essa restrição.
- A tradução LLTZ atual da desestruturação projeta a expressão em dois pontos.
  Isso preserva os casos puros atualmente compiláveis, mas deverá usar um
  binding temporário único quando chamadas ou efeitos forem suportados.

Essas limitações não impedem o parser, type checker ou interpretador do
Project 2, mas devem ser mencionadas ao apresentar o estágio de geração de
código.

## 9. Perguntas esperadas na defesa

**Por que pair é estrutural e enum é nominal?**

Um pair é definido pelos tipos de seus componentes. Um enum expressa uma
identidade declarada no domínio; dois enums com formato parecido não devem se
tornar intercambiáveis por acidente.

**Por que as variantes carregam `unit` no LLTZ?**

As variantes do projeto não possuem payload. `unit` fornece um valor único
para ocupar cada alternativa do tipo soma sem acrescentar informação.

**Por que verificar exaustividade estaticamente?**

Isso garante que qualquer valor válido do enum selecione um branch e permite
ao interpretador tratar a ausência de branch como violação interna, não como
controle de fluxo normal.

**Como um enum de três variantes cabe no `or` binário de Michelson?**

Por uma árvore aninhada, por exemplo `or unit (or unit unit)`. As injeções e o
match tornam-se sequências aninhadas de `LEFT`/`RIGHT` e `IF_LEFT`. O IR LLTZ
representa a row n-ária, mas o lowering concreto ainda não existe no projeto.

**Por que o codec precisa do registro de enums?**

O tipo `TEnum "Color"` sozinho contém apenas o nome nominal. Para decidir se
uma string externa é uma variante válida, o decoder precisa consultar a
declaração `Color -> [variantes]`.

## 10. Conformidade com README e documentação upstream

| Referência | Situação da implementação |
|---|---|
| `README.md`: `cabal build` e `cabal test` | Conforme; executável, biblioteca e suíte compilam com GHC 9.10.3. |
| `docs/02-pipeline.md`: parser → type checker → interpretador → persistência | Conforme para execução SmartTS; o type checker atual produz `TypedContract`, evolução já presente na `main`. |
| `docs/03`–`docs/06`: AST, parser, checker e interpretador da linguagem-base | A extensão preserva os comportamentos existentes e adiciona construtores/casos sem remover funcionalidades. |
| `docs/09-projects.md`: pair estrutural | Conforme em AST, parser, igualdade, checker, interpretador e LLTZ. |
| `docs/09-projects.md`: `fst`/`snd` | Conforme, com projeções tipadas e execução coberta por testes. |
| `docs/09-projects.md`: desestruturação | Conforme para `var` e `val`, criando dois bindings simultaneamente. |
| `docs/09-projects.md`: enum nominal e registro separado | Conforme por `envEnumDefs` e `envVariantEnum`. |
| `docs/09-projects.md`: variantes como valores e igualdade | Conforme no checker e interpretador. |
| `docs/09-projects.md`: match exaustivo | Conforme; ausência, duplicação e cases desconhecidos falham estaticamente. |
| `docs/09-projects.md`: testes e samples | Testes automatizados passam; `TrafficLight.smartts` e `VotingBox.smartts` exercitam os recursos no diretório `samples/`. |
| Terceiro milestone: geração de código | Conforme no nível SmartTS → LLTZ para os recursos do Project 2; não deve ser descrito como backend Michelson completo. |

Alguns textos upstream ainda citam `lib/SmartTS/AST.hs`, um AST não
parametrizado, retorno `Right ()` do type checker ou somente dois grupos de
testes. Essas descrições já estavam defasadas em relação à arquitetura da
`main` usada como base. Elas foram mantidas intactas nesta branch, conforme a
política de não editar documentação upstream; este adendo registra a realidade
da extensão sem reescrever o material original.

As restrições de no mínimo duas variantes, capitalização e unicidade global
não são exigidas literalmente por `docs/09-projects.md`. Elas são decisões da
implementação necessárias para tornar segura a sintaxe não qualificada e a
representação direta por soma. Por isso devem ser apresentadas como escolhas
do grupo, não como regras impostas pelo enunciado.
