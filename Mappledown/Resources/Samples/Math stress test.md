# Math stress test

This file checks that Mappledown renders hard LaTeX correctly. Open it in Split view and compare the source with the preview.

## Inline math, four ways

Dollar signs: $e^{i\pi} + 1 = 0$, parentheses: \(\int_0^1 x^2\,dx = \tfrac13\), and a price that must **not** become math: it costs $5 and $6 today. An escaped dollar: \$10.

Inline display with double dollars inside a sentence: $$\sum_{n=1}^\infty \frac{1}{n^2} = \frac{\pi^2}{6}$$ and the sentence continues.

## Display math

$$
I = \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

\[
\oint_{\partial \Sigma} \mathbf{B}\cdot d\boldsymbol{\ell} = \mu_0 \iint_{\Sigma} \mathbf{J}\cdot d\mathbf{S} + \mu_0\varepsilon_0 \frac{d}{dt}\iint_{\Sigma}\mathbf{E}\cdot d\mathbf{S}
\]

$$ \det(A - \lambda I) = 0 $$

## Numbered environments

\begin{align}
f(x) &= \begin{cases}
  x^2 & x \ge 0 \\
  -x  & x < 0
\end{cases} \label{eq:piecewise} \\
g(x) &= \int_0^x f(t)\,dt \notag \\
\nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t}
\end{align}

Equation \eqref{eq:piecewise} is piecewise.

\begin{equation}
\mathcal{F}\{f\}(\xi) = \int_{-\infty}^{\infty} f(x)\, e^{-2\pi i x \xi}\, dx
\end{equation}

\begin{gather*}
a^2 + b^2 = c^2 \\
(a+b)^n = \sum_{k=0}^{n} \binom{n}{k} a^{n-k} b^k
\end{gather*}

\begin{multline}
p(x) = 3x^6 + 14x^5y + 590x^4y^2 + 19x^3y^3 \\
- 12x^2y^4 - 12xy^5 + 2y^6 - a^3b^3
\end{multline}

## Matrices and arrays

$$
A = \begin{pmatrix} 1 & 2 & \cdots & n \\ 2 & 4 & \cdots & 2n \\ \vdots & \vdots & \ddots & \vdots \\ n & 2n & \cdots & n^2 \end{pmatrix},
\qquad
\det\begin{vmatrix} a & b \\ c & d \end{vmatrix} = ad - bc
$$

$$
\left[\begin{array}{cc|c}
1 & 0 & 3 \\
0 & 1 & -2
\end{array}\right]
$$

## Macros, boxes, colours, text

$\newcommand{\R}{\mathbb{R}}\newcommand{\norm}[1]{\left\lVert #1 \right\rVert}$For any $x \in \R^n$, $\norm{x}^2 = \sum_i x_i^2$.

$$
\boxed{E = mc^2} \qquad {\color{red}\text{red}} \quad \underbrace{a + b + \cdots + z}_{26} \quad \overset{\text{def}}{=} \quad \xrightarrow[\text{under}]{\text{over}}
$$

$$
\DeclareMathOperator*{\argmax}{arg\,max}
\theta^\ast = \argmax_{\theta} \; \mathbb{E}_{x \sim p}\!\left[\log q_\theta(x)\right]
$$

## Math inside other Markdown

- A list item with $\alpha + \beta$
- A nested list:
  1. $\lim_{n\to\infty}\left(1 + \frac1n\right)^n = e$
  2. $\displaystyle \prod_{p\ \text{prime}} \frac{1}{1-p^{-s}} = \zeta(s)$

> A quote with math: $\hbar \frac{\partial}{\partial t}\Psi = \hat H \Psi$

| Name | Formula |
| --- | --- |
| Euler | $e^{i\theta} = \cos\theta + i\sin\theta$ |
| Stirling | $n! \sim \sqrt{2\pi n}\left(\frac{n}{e}\right)^n$ |

Code is left alone: `$not math$` and

```python
price = "$5 and $6"   # still code
print(r"\frac{a}{b}")
```

## Errors

A broken formula should show in red with the reason: $\frac{1}$ and $\undefinedcommand{x}$.

Footnote test.[^1]

[^1]: A footnote with math $\varphi = \frac{1+\sqrt5}{2}$.
