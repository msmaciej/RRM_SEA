	  *****************************************************
			   TANLY32 - TechAnly 32 Bit
			   FIS LTD
			   Evaluation Version 7.0
			   Release Date - Apr 1997
	  *****************************************************

FIS Ltd. provides a limited license for you to evaluate this product
for a period of 30 days in your own work environment. This "try before
you buy" approach allows you to determine if the product meets your
individual needs before you purchase it.If you continue to use this
product after the 30 day evaluation period, you are required to
purchase a licensed version.
     
PLEASE READ THIS ENTIRE FILE AND DISCLAIM.TXT BEFORE INSTALLING
AND USING TANLY32.XLL.

______________________________________________________________________


Installation
************

The evaluation version of TANLY32 is provided in compressed format
(i.e. in ZIP format)

     1. The simplest form of installation is to copy the compressed
	file to a single directory (i.e. \TANLY32).  If you have a
	previous version of TANLY32 on your hard drive, and you want
	to retain it, create a different directory (i.e., \TANLYBKP).

     2. Decompress the file using the decompression program. All
	distribution files should remain in the same directory.
	(e.g. pkunzip TANLY32.zip)

     3. Start Excel 7 (or later) and load TANLY32.XLL addin.

     4. Open TECHANLY.XLS to see how to use the addin.


List of Files
-------------

DISCLAIM.TXT
ORDER.TXT
README.TXT
TANLY32.XLL
TECHANLY.XLS

______________________________________________________________________


Overview
********

TANLY32.XLL is an Excel addin for Excel 7 or later which provides the
user with a comprehensive suite of technical analysis models to assist
in the prediction and confirmation of price movements for any type of 
instrument in all kinds of market cycles.

The addin incorporates the most widely used models since experience
confirms that no single system can be relied upon continuously.
Certain models are better suited than others depending upon the market
phase, and in certain situations, the On Balance Volume tool confirms
or identifies price movements which are not apparent from the price
tools.

Models include:-
		Regular Moving Average
		Exponential Moving Average
		Weighted Moving Average
		Relative Strength Index
		Percentage Range
		Momentum
		Oscillators
		Stochastics
		Ratios
		Standard Deviation
		Correlation
		On Balance Volume

______________________________________________________________________


Function Description and Prototype
**********************************


Regular, Weighted and Exponential Moving Average Charts
-------------------------------------------------------

Moving Averages provide a method to smooth the data to remove erroneous
price movements and highlight where the market is trending. Crossovers
between price and moving average lines indicate possible breakout
signals.

Function prototypes:-   RegMovAvg(DataRange, Period)
			WeightMovAvg(DataRange, Period)
			ExpMovAvg(DataRange, WeightingFactor)

 
Relative Strength Index
-----------------------

Wilder’s Relative Strength Index (RSI) is a prediction and confirmation
tool that identifies overbought and oversold situations and the fact
that the values are normalised between 0 and 100% allows the comparison
of different instruments.

Function prototype:-    RelStrIndex(DataRange, Period)


Percentage Range
----------------

William’s Percentage range compares the closing price with the range
of closing prices over the selected period of days. Overbought
indications are identified when the price is close to the highest
price from the range, whilst oversold situations are identified when
the price is close to the lowest price from the range.

Function prototype:-    PercRange(DataRange, Period)


Momentum and Oscillators
------------------------

Oscillators and Momentum charts indicate the impetus left in a price
swing. The Oscillator model is normalised to allow the comparison of
different instruments.

Function prototypes:-   Momentum(DataRange, Period)
			Oscillators(DataRange, Period)


Stochastics
-----------

Lane’s Stochastics employ four indicators; %K Indicator, %D Indicator,
%D-Slow and MA %D-Slow, which combine Percentage Range, Relative
Strength and Moving Average methods to predict market trends. The
combination of the tools allow the Stochastics model to be utilised in
various market cycles.

Function prototype:-    LanesStochs(DataRange, %K_Period,
						%D_Period, MA_Period)


Standard Deviation
------------------

Measures how widely values are dispersed from the average value.

Function prototype:-    StandardDeviation(DataRange, Period)


Correlation
-----------

Correlation is determined by comparing two instruments daily percentage
price changes to give a measure of the price change of one instrument
relative to the other instrument.

Function prototype:-    Correlation(X_DataRange, Y_DataRange)


Ratio
-----

Ratio measures the ratio between two instruments daily prices, which
when combined with the correlation model provide a powerful method
for pairs trading and basket trading.

Function prototype:-    Ratio(Data1Range, Data2Range)


On Balance Volume
-----------------

OBV indicates the strength of price trends, whether advance or decline.
For example, a bullish or bearish signal is highlighted when the OBV
and price directions are the same and not the same respectively.

Function prototype:-    OnBalVolume(PriceRange, VolumeRange)

______________________________________________________________________


How To Use TANLY32 Functions
*****************************

Function Arguments
------------------

All Arguments to the functions are either a numeric array or a number.

DataRange refers to the numeric array and should be a ONE COLUMN range
of cells with an unlimited number of rows (i.e. n rows by 1 column).

Period refers to the fixed number of days over which to run the model
each day.

WeightingFactor, between 0 and 1, refers to the factor by which more
recent data influences the model.


Function Results
----------------

All the functions return an array of results. In general the functions
will return an array size equal to the size of the array entered.
Therefore if the argument array has (n rows by 1 column) then the
results array will have n values.

When selecting a range of cells for the results array, users are
recommended to usually select a ONE COLUMN RANGE of cells with the
same number of rows as the argument array. In this way each result
value can be matched up with its data value (See TECHANLY.XLS).

The exceptions to this rule are:-

The Correlation function which will return an array with 3 values
corresponding to R2, intercept and correlation.

The LanesStochs function which will return an array with
(n rows by 4 columns) because this function returns four sets of
results.


Entering Array Formulae
-----------------------

Users who are not familiar on how to enter an array formula please
read the following:-

1) Enter the formula in the cell. You can use the function wizard to
   guide you. The first value from the array of results will be
   entered in the cell.

2) Starting from the cell where you entered the function, select the
   range of cells where the function will return the whole array of
   results.

3) Press Function key F2 to edit the formula.

4) Press CTRL+SHIFT+ENTER. The array of results will be entered into
   the selected range of cells.

For more information on how to enter array formula please refer to
the Excel online help (Search for "Entering an array formula").


Please refer to TECHANLY.XLS to see how models are used.

______________________________________________________________________


Registering as a Licensed User
******************************

As a registered user, you will receive a licensed copy of the latest
TANLY32.XLL addin. The differences between the licensed copy and
the evaluation copy are:-

1) Models are not restricted to the number of data points in the
   array(45 data points at most)
2) Periods are not restricted to either 5 or 14
3) Weighting factors are not restricted to either 0.2 or 0.8

In such cases the evaluation copy will return #N/A's.

Please refer to the file order.txt for details on how to register for
your licensed copy.

Please feel free to contact us at any time if you have any questions,
comments or suggestions at:-

	FIS Ltd.
	28 Drakes Drive
	Northwood, Middx. HA6 2SL
	UK

Or:-    Electronic Mail: FIS_LTD@compuserve.com

	http://ourworld.compuserve.com/homepages/fis_ltd