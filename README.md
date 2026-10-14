# penumbra

![](https://user-cdn.hackclub-assets.com/01a13c5c-26c1-7cf3-8cdf-27fb133c66d4/penumbra-1197929-2940x1912.png)

a shader for [wpr](https://github.com/maxwofford/wpr), the wallpaper manager. ported from the [hack club penumbra](https://penumbra.hackclub.com/) landing page by [ascpixi](https://ascpixi.dev), with crt pass after [Xor](https://www.shadertoy.com/view/DtscRf) and bloom after [Xor's 1-pass blur](https://github.com/XorDev/1PassBlur).

```sh
brew tap maxwofford/wpr && brew install wpr   # if you don't have wpr yet
wpr install maxwofford/penumbra
wpr gen penumbra                              # a new one, set as your wallpaper
wpr enable penumbra                           # add it to your rotation
```

## local development

wanna clone and iterate on the design?

```sh
git clone https://github.com/maxwofford/wpr-penumbra
wpr install ./wpr-penumbra
wpr gen penumbra
```
