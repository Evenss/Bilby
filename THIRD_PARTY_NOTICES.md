# Third-party notices

Bilby's original code and resources are licensed under the [MIT License](LICENSE).
Third-party assets retain their own licenses as described below.

## Remix Icon — GitHub link icon

The footer link uses `github-line.svg` from
[Remix Icon](https://github.com/Remix-Design/RemixIcon/blob/master/icons/Logos/github-line.svg),
copyright (c) 2017–2026 Remix Design, under the Remix Icon License v1.0.
It represents a link to the Bilby repository on GitHub. The icon is not covered
by Bilby's MIT License.

The original SVG is included without path changes; `GitHubLink.pdf` is the native
vector resource derived from it, with `currentColor` resolved to black for
template rendering. Regenerate it with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift Tools/GenerateGitHubIcon.swift Resources/GitHub.svg Resources/GitHubLink.pdf
```

A copy of the icon license
is in `Resources/ThirdParty/RemixIcon.LICENSE` in this repository and
`Contents/Resources/ThirdParty/RemixIcon.LICENSE` in the built app.

## Hidden Bar — visibility bridge

The macOS 27 visibility mechanism and runtime bridge were informed by
[Hidden Bar](https://github.com/dwarvesf/hidden), especially
`HBNativeVisibilityShim.m` and `NativeVisibilityEngine.swift`.
The application and its layout, user interface, persistence and local ordering code
were implemented for this project.

MIT License

Copyright (c) 2019 Dwarves Foundation

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
