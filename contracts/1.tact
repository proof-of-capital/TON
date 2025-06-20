сделай переводы всех коментариев

    // Updates the offset for a given amount of added tokens,
    // adjusting the current step, remainder, and price.
    //
    // Main steps:
    // - Iterates over the remaining amount of tokens to be added.
    // - For each step, calculates the available number of tokens.
    // - If the added tokens are enough to fill the step, decreases the remainder,
    //   and updates step parameters and price based on the current level.
    // - If the tokens are not enough, partially increases the step remainder.
    // - Updates global offset parameters and the current step.
    // - Decreases the total number of sold tokens by the added amount.
    //
    // Returns:
    // - The current step after recalculation.


       // Calculates the number of tokens to be issued for a given support amount.
    //
    // Logic:
    // - Initializes local variables for the current step, remainder, tokens per level, and price.
    // - In a loop, while there is remaining support and tokens available to issue:
    //   - Determines the available number of tokens at the current step and the required TON amount to purchase them.
    //   - If the support is sufficient for a full step:
    //     - Increases the number of tokens to issue by the full step amount.
    //     - Calculates and accumulates profit for that step.
    //     - Moves to the next step, recalculating tokens per level and price.
    //   - If the support is insufficient for a full step:
    //     - Calculates how many tokens can be bought with the remaining support.
    //     - Adds them to the total number to be issued.
    //     - Calculates and adds profit for this partial step.
    //     - Sets the remaining support to zero and adjusts the step remainder.
    // - If more tokens are requested than available, limits issuance to the maximum remaining.
    // - Updates offset state, current step, price, and profit.
    //
    // Returns:
    // - The number of tokens to be issued.




       // Calculates the support amount (supportAmountToPay) required to purchase a given number of tokens (tokenAmount).
    //
    // Logic:
    // - Uses local copies of the current step, step token remainder, price, and tokens per level.
    // - While there are tokens left to pay for:
    //   - Determines the number of tokens available at the current step.
    //   - If the remaining token amount is greater than or equal to the available tokens in the step:
    //     - Calculates the profit percentage for the current step.
    //     - Adjusts the price with the profit.
    //     - Calculates the support amount for the full step and adds it to the total payment.
    //     - Reduces the remaining token amount.
    //     - Updates level parameters and price when transitioning to a new step.
    //     - Adjusts the step and step token remainder based on the current state.
    //   - If the token amount is less than the available tokens in the step:
    //     - Calculates the support amount for the partial token quantity similarly.
    //     - Updates the step token remainder.
    //     - All tokens are paid — the loop ends.
    // - Updates the contract state: current step, tokens per level, current price, and remainder.
    //
    // Returns:
    // - The total support amount to be paid.




        // Calculates the support amount (supportAmountToPay) required to be paid for a given number of earned tokens (tokenAmount).
    //
    // Logic:
    // - Uses local copies of the current earned step, step token remainder, price, and tokens per level.
    // - While there are tokens left to pay for and the current step does not exceed the maximum step:
    //   - Determines the number of tokens available at the current step (remainder).
    //   - If the remaining token amount is greater than or equal to the available remainder:
    //     - Calculates the profit percentage for the current step.
    //     - Adjusts the price including the profit.
    //     - Calculates the support amount for the full remainder and adds it to the total payment.
    //     - Proceeds to the next step.
    //     - Updates the number of tokens per level (jettonsPerLevel) using the calculateJettonsPerLevel function.
    //     - Sets the new remainder to the updated tokens per level.
    //     - Decreases the remaining token amount.
    //     - Updates the current price using the increment multiplier.
    //   - If fewer tokens remain than available in the remainder:
    //     - Similarly calculates the support amount for the partial token quantity.
    //     - Updates the remainder by subtracting the paid tokens.
    //     - Ends the loop (all tokens are paid).
    // - After the loop, updates the contract state (current earned step, tokens per level, current price, and remainder).
    //
    // Returns:
    // - The total support amount to be paid.
