class Neutral{
    static run(){
        var character = World.getAvatarCharacter()
        var irritation = character.getStatistic(STATISTIC_IRRITATION);
        if(irritation==null || irritation == NaN){
            character.setStatistic(STATISTIC_IRRITATION,0);
        }
        var maximumIrritation = character.getStatistic(STATISTIC_MAXIMUM_IRRITATION);
        if(maximumIrritation==null || maximumIrritation == NaN){
            character.setStatistic(STATISTIC_MAXIMUM_IRRITATION,100);
        }
        Utility.saveGame();
        try{
            Navigation.run();
        }
        catch(e){
            World.abandon();
            Utility.abandonGame();
            MainMenu.run();
        }
    }
}