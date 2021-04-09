package com.sogeti.CoinCounter

class Money(val id: String) {

    val currency: String
    val amount: Float
    val isValid: Boolean


    init {
        amount = 0f
        currency = ""

        //TODO: do thiiis
        isValid = (id != "" && id != "dump")
    }

}