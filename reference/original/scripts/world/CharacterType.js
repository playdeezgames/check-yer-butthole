class CharacterType{
    static descriptors = {
        N00b:{
            initialize: (character)=>{
                character.setStatistic(STATISTIC_BUTTHOLE_CHECKS, 0);
                character.setStatistic(STATISTIC_EXPERIENCE_POINTS, 0);
                character.setStatistic(STATISTIC_EXPERIENCE_GOAL, 100);
                character.setStatistic(STATISTIC_EXPERIENCE_LEVEL, 0);
                character.setStatistic(STATISTIC_ADVANCEMENT_POINTS, 0);
                character.setStatistic(STATISTIC_IRRITATION,0);
                character.setStatistic(STATISTIC_MAXIMUM_IRRITATION,100);
            }
        }
    };
    static initialize(characterType, character){
        CharacterType.descriptors[characterType].initialize(character);
    }
}