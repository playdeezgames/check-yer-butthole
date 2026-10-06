class Character{
    constructor(worldData, characterId){
        this.worldData=worldData;
        this.characterId=characterId;
    }
    getCharacterData(){
        return this.worldData.characters[this.characterId];
    }
    getId(){
        return this.characterId;
    }
    setName(name){
        this.getCharacterData().name=name;
    }
    getName(){
        return this.getCharacterData().name;
    }
    setStatistic(statisticType, value){
        let characterData = this.getCharacterData();
        if(characterData.statistics==null){
            characterData.statistics={};
        }
        if(value == null){
            delete characterData.statistics[statisticType];
        }else{
            characterData.statistics[statisticType] = value;
        }
    }
    getStatistic(statisticType){
        let characterData = this.getCharacterData();
        if(characterData.statistics == null){
            return null;
        }
        return characterData.statistics[statisticType];
    }
    changeStatistic(statisticType, delta){
        this.setStatistic(statisticType, this.getStatistic(statisticType) + delta);
    }
    setAdvancement(advancementType, value){
        let characterData = this.getCharacterData();
        if(characterData.advancements==null){
            characterData.advancements={};
        }
        if(value == null){
            delete characterData.advancements[advancementType];
        }else{
            characterData.advancements[advancementType] = value;
        }
    }
    getAdvancement(advancementType){
        let characterData = this.getCharacterData();
        if(characterData.advancements==null || characterData.advancements[advancementType] == null){
            return 0;
        }
        return characterData.advancements[advancementType];
    }
}