# templates-benchmark-tt-xslate

A little benchmark comparing the speed of two Perl-based templating systems:

- TT - https://metacpan.org/pod/Template
- XS - https://metacpan.org/pod/Text::Xslate

To run, "just" run `make`.

You'll need `perl` and `carton` installed.

The benchmarks vary from small one-liners to bigger units. The aim is to see
how much faster `Text::Xslate` is compared to `Template`, when told to do the
same things given the same data.

As part of each "test", it verifies that the output from both types of
templates, given the same data, is the same - so we're comparing apples to
apples.

Example run from my machine:

```bash
$ make
carton exec perl benchmark.pl 0.5 
Function                                   TT/s     TX/s      ±TX/TT    ±TX/TTx
0.5s elreg_801_events_row                    955.83   7859.61  +722.28%  +7.22x
0.5s elreg_800_events_row                   1204.80   8303.59  +589.21%  +5.89x
0.5s 200_full_homepage                       532.45   5135.75  +864.55%  +8.65x
0.5s 101_runtime_inclusion_dynamic          1806.12  14928.16  +726.53%  +7.27x
0.5s 100_runtime_inclusion                  5107.42  54002.19  +957.33%  +9.57x
0.5s 092_stories_list_wrapped_twice         2693.65  23063.88  +756.23%  +7.56x
0.5s 091_stories_list_wrapped               1979.03  22143.03 +1018.88% +10.19x
0.5s 090_stories_list                       3091.75  19702.71  +537.27%  +5.37x
0.5s 031_include_without_macro_call         1728.71  33046.92 +1811.65% +18.12x
0.5s 030_include_for_macro_call             1559.42  28046.79 +1698.54% +16.99x
0.5s 020_macro_loop_data                    3692.58  66671.20 +1705.54% +17.06x
0.5s 020_macro_loop                         4186.85  80391.34 +1820.09% +18.20x
0.5s 011_include_small_variable            11121.05 211209.44 +1799.19% +17.99x
0.5s 010_include_small_literal             13468.77 222938.28 +1555.22% +15.55x
0.5s 005_deep_data_structure               19035.89 207136.43  +988.14%  +9.88x
0.5s 004_simple_loop_if_else_constant       1665.96  15678.62  +841.12%  +8.41x
0.5s 004_simple_loop_if_else                1719.08  16453.41  +857.11%  +8.57x
0.5s 003_urls_pipe_uri                      8207.14  69471.47  +746.48%  +7.46x
0.5s 002_simple_loop_vars                   5058.91  68635.39 +1256.72% +12.57x
0.5s 002_simple_loop                        1765.36  15995.13  +806.06%  +8.06x
0.5s 001_simple_loop                       10105.90 241775.15 +2292.42% +22.92x
0.5s 001_simple_hashref                     9365.64  98889.16  +955.87%  +9.56x
0.5s 000_two_vars                          18910.05 259079.86 +1270.06% +12.70x
0.5s 000_single_var                        20107.43 321045.35 +1496.65% +14.97x
0.5s 000_reuse_macro_call                  12899.76 237135.00 +1738.29% +17.38x
0.5s 000_literal_text                      21577.90 371321.00 +1620.84% +16.21x
carton exec perl benchmark.pl 1 
Function                                   TT/s     TX/s      ±TX/TT    ±TX/TTx
1s   elreg_801_events_row                   1087.98   9590.83  +781.52%  +7.82x
1s   elreg_800_events_row                   1183.25   7990.54  +575.31%  +5.75x
1s   200_full_homepage                       431.13   4670.24  +983.27%  +9.83x
1s   101_runtime_inclusion_dynamic          2850.87  22436.50  +687.00%  +6.87x
1s   100_runtime_inclusion                  4991.05  53384.00  +969.59%  +9.70x
1s   092_stories_list_wrapped_twice         2564.53  25203.86  +882.79%  +8.83x
1s   091_stories_list_wrapped               2862.19  20142.49  +603.74%  +6.04x
1s   090_stories_list                       2924.59  28458.26  +873.07%  +8.73x
1s   031_include_without_macro_call         1973.14  33524.71 +1599.06% +15.99x
1s   030_include_for_macro_call             1489.50  29940.59 +1910.10% +19.10x
1s   020_macro_loop_data                    3341.57  59345.76 +1675.99% +16.76x
1s   020_macro_loop                         2168.45  76751.04 +3439.44% +34.39x
1s   011_include_small_variable             9819.71 180714.59 +1740.32% +17.40x
1s   010_include_small_literal             11813.23 210217.54 +1679.51% +16.80x
1s   005_deep_data_structure               15825.56 212695.95 +1244.00% +12.44x
1s   004_simple_loop_if_else_constant       1627.98  14046.82  +762.84%  +7.63x
1s   004_simple_loop_if_else                2241.70  19211.24  +756.99%  +7.57x
1s   003_urls_pipe_uri                      7622.16  54098.00  +609.75%  +6.10x
1s   002_simple_loop_vars                   4513.68  52679.26 +1067.10% +10.67x
1s   002_simple_loop                        1506.91  14390.59  +854.97%  +8.55x
1s   001_simple_loop                        8457.82 189942.38 +2145.76% +21.46x
1s   001_simple_hashref                     7313.46  71364.34  +875.79%  +8.76x
1s   000_two_vars                          16630.36 288870.52 +1637.01% +16.37x
1s   000_single_var                        17143.30 278697.99 +1525.70% +15.26x
1s   000_reuse_macro_call                  11125.50 209345.89 +1781.68% +17.82x
1s   000_literal_text                      18906.49 275176.78 +1355.46% +13.55x
carton exec perl -MTemplate -MText::Xslate -E'say "TT $Template::VERSION TX $Text::Xslate::VERSION"'
TT 3.100 TX v3.5.6
```

The above shows `Text::Xslate` as being between 5-30 times faster as `Template`.
