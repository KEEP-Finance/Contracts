# Record

## TODOs

1. add a lending pool aggregator, which can do the following

    - Get all available pools

    - Add / Remove pools

    - Basic pool Actions, including supplying / borrowing / withdrawing / repaying via a unified function -- I think we can do this by just calling different pools in the frontend

    - Remove unwanted functions

        - stable loan

        - change atoken name

        - 

2. Leveraged positions

    - A list of allowed asset address to be provided as collateral (Currently only in main pool)

    - Outside dex (1INCH) -- can swap tokens to the one we want
    
        - 1INCH is the dex we use for the hackathon

        - 1INCH calldata feed from frontend

        - 1INCH price oracle from frontend

        - feed calldata into 1INCH contract -- first figure out the contract address

        - Swap

            for the swaps, there are currently two choices: the first is to put the path information as input of the contract; the second is to put the path information abstracted from contract abi (implemented inside the function)

    - Price oracle -- precisely get mark price (pnl estimation and prevent unfair liquidation) and index price from dex.
        
        - Mark Price is the 15min twap on DEX

        - Index Price is the actual price on DEX
    
    - Open position

        - Check remaining margin (cross margin on default, can specify isolated)

        - identify the asset / pool to borrow (I think currently we only allow main pool as margin supply and as asset to borrow)

        - Auto swap and then record swap price (consider slippage, avoid sandwich attacks -- we may need to input desired price from frontend)

        - Lock swapped asset into vault
    
    - Close Position

        - Auto swap and calculate pnl (consider slippage as well)

        - update user's margin amount

        - NOTE: we need to tackle situations where the user's remaining asset is negative (Insurance Fund, later implement)
    
