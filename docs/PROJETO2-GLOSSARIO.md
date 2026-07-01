# Project 2 — Glossário técnico e didático

## Uso

Cada termo contém uma definição técnica, uma tradução didática e sua aplicação
no projeto. O objetivo é evitar respostas com palavras corretas, mas conceitos
misturados.

### AST — Abstract Syntax Tree

**Técnico:** árvore que representa a estrutura sintática relevante sem guardar
cada detalhe textual. **Didático:** a planta do programa depois de retirar
pontuação decorativa. **No projeto:** `Expr a`, `Stmt a` e `Contract a`.

### Anotação de tipo

**Técnico:** informação associada a um nó da árvore parametrizada.
**Didático:** uma etiqueta dizendo o tipo do resultado daquele trecho.
**No projeto:** `()` após parsing e `Type` após checking.

### Binding

**Técnico:** associação entre nome, tipo, mutabilidade e eventualmente valor.
**Didático:** uma entrada de agenda para descobrir o que um nome significa.
**No projeto:** parâmetros e locais em `envBindings`/`rtLocals`.

### Tipo estrutural

**Técnico:** igualdade determinada pela forma e pelos componentes.
**Didático:** duas caixas são compatíveis se seus compartimentos têm o mesmo
formato. **No projeto:** `TPair`.

### Tipo nominal

**Técnico:** igualdade determinada pela identidade declarada do tipo.
**Didático:** dois documentos continuam diferentes mesmo com campos iguais.
**No projeto:** `TEnum Name`.

### Tipo produto

**Técnico:** tipo cujo valor contém simultaneamente valores de todos os fatores.
**Didático:** “A e B”. **No projeto:** `pair<T,U>`/`TTuple`.

### Tipo soma

**Técnico:** tipo cujo valor ocupa exatamente uma entre várias alternativas.
**Didático:** “A ou B”. **No projeto:** enum/`TOr`/Michelson `or`.

### Tipo parametrizado

**Técnico:** construtor de tipo que recebe outros tipos como argumentos.
**Didático:** um molde preenchido com materiais escolhidos. **No projeto:**
`pair<T,U>`.

### Variante

**Técnico:** alternativa nomeada de um tipo soma nominal. **Didático:** uma das
opções válidas de um catálogo. **No projeto:** `Red` em `Color`.

### Registro de tipos

**Técnico:** ambiente que associa nomes nominais às suas definições.
**Didático:** catálogo de categorias do contrato. **No projeto:**
`envEnumDefs` e `envVariantEnum`.

### Tabela de símbolos

**Técnico:** ambiente de nomes de valores visíveis no escopo atual.
**Didático:** lista de variáveis disponíveis na sala atual. **No projeto:**
`envBindings`.

### Escopo

**Técnico:** região na qual um binding é visível. **Didático:** área de validade
de um crachá. **No projeto:** `withSavedEnv` impede vazamento entre branches.

### Inferência de tipo

**Técnico:** cálculo do tipo de uma expressão a partir de suas regras e
subexpressões. **Didático:** descobrir a etiqueta do resultado pelas etiquetas
das peças. **No projeto:** `inferExpr`.

### Invariante

**Técnico:** propriedade que deve permanecer verdadeira em determinado ponto
do pipeline. **Didático:** regra que, depois de conferida na entrada, pode ser
assumida internamente. **No projeto:** variante literal sempre pertence ao enum.

### Exaustividade

**Técnico:** cobertura de todos os valores possíveis de um tipo soma.
**Didático:** nenhuma opção do catálogo fica sem instrução. **No projeto:** todo
enum case deve aparecer no `match`.

### Desestruturação

**Técnico:** eliminação de um produto que introduz bindings para seus
componentes. **Didático:** abrir a caixa e nomear cada compartimento. **No
projeto:** `VarDestructStmt` e `ValDestructStmt`.

### Mutabilidade

**Técnico:** permissão para substituir o valor associado a um binding.
**Didático:** etiqueta que pode ou não ser reescrita. **No projeto:** `var`
versus `val`.

### Codec

**Técnico:** camada que converte representação interna para/de formato externo.
**Didático:** tradutor entre valores SmartTS e JSON. **No projeto:**
`Interpreter/Codec.hs`.

### IR — Intermediate Representation

**Técnico:** representação intermediária entre linguagem-fonte e alvo.
**Didático:** planta intermediária usada antes das instruções finais. **No
projeto:** LLTZ.

### LLTZ

**Técnico:** IR tipado usado para expressar funções, produtos, somas e controle
antes de Michelson. **Didático:** vocabulário intermediário mais próximo do
modelo formal. **No projeto:** `IR/LLTZ.hs`.

### Row

**Técnico:** árvore de campos/alternativas, possivelmente rotulados, usada por
tuplas e somas n-árias. **Didático:** mapa ordenado das gavetas de um produto ou
soma. **No projeto:** `RowNode` e `RowLeaf`.

### Injeção

**Técnico:** construção de um valor de soma escolhendo uma alternativa.
**Didático:** colocar um valor em uma gaveta específica. **No projeto:** `Inj`;
em Michelson, `LEFT`/`RIGHT`.

### Projeção

**Técnico:** extração de componente de um produto por caminho/posição.
**Didático:** abrir a gaveta 0 ou 1. **No projeto:** `Proj`; intenção `CAR`/`CDR`.

### Payload

**Técnico:** dado transportado por uma alternativa de soma. **Didático:** o
conteúdo dentro do envelope da variante. **No projeto:** variantes são
nulárias, então carregam `unit`.

### `unit`

**Técnico:** tipo com um único valor, usado quando não há informação útil.
**Didático:** envelope vazio padronizado. **No projeto:** payload das variantes
LLTZ.

### Stack typing

**Técnico:** descrição de instrução como transformação entre tipos de stack.
**Didático:** contrato que diz quais peças entram no topo da pilha e quais
saem. **No projeto:** `PAIR :: ty1 : ty2 : A -> pair ty1 ty2 : A`.

### Lowering

**Técnico:** tradução de uma representação abstrata para outra mais concreta.
**Didático:** converter a planta intermediária em instruções executáveis.
**No projeto:** LLTZ → Michelson ainda não implementado.

### Semântica operacional

**Técnico:** regras que descrevem como estados/valores mudam durante execução.
**Didático:** passo a passo do que a máquina faz. **No projeto:** `Eval.hs`.

### Fronteira de confiança

**Técnico:** ponto em que dados externos precisam ser validados antes de ganhar
garantias internas. **Didático:** portaria do sistema. **No projeto:** decoder
JSON com `EnumRegistry`.

### `interpretBug`

**Técnico:** falha para estado considerado impossível após type checking.
**Didático:** alarme de que uma garantia interna foi quebrada, não mensagem
normal de usuário. **No projeto:** match sem case após árvore tipada.

### Função parcial

**Técnico:** função que não produz resultado para todo valor do domínio, como
`head []`. **Didático:** ferramenta que quebra em uma entrada não prevista.
**No projeto:** warning removido por pattern matching em branches.

### Rastreabilidade

**Técnico:** ligação verificável entre requisito, implementação e teste.
**Didático:** trilha para provar onde cada promessa foi cumprida. **No projeto:**
[matriz de rastreabilidade](PROJETO2-MATRIZ-RASTREABILIDADE.md).

## Contrastes que devem estar claros

| Não confundir | Diferença |
|---|---|
| Parser × checker | forma sintática × validade semântica/tipos |
| Binding × tipo nominal | nome de valor em escopo × identidade de tipo |
| Pair × enum | produto estrutural × soma nominal |
| Variante × enum | alternativa/valor × tipo que agrupa alternativas |
| `RIGHT` × `IF_LEFT` | constrói soma × elimina/inspeciona soma |
| LLTZ × Michelson | IR intermediário × linguagem alvo de stack |
| Teste × prova formal | exemplos automatizados × garantia para todos os casos |
| Erro do usuário × `interpretBug` | entrada inválida esperada × invariante interno quebrado |

