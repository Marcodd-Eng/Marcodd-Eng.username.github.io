USE [DRS]
GO
/****** Object:  StoredProcedure [dbo].[sp_test_001]    Script Date: 20/10/2021 11:19:13 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

--------------------------------------------------------------------
--20160405 - Laura Babaneri - problema posizionale sigi - utilizzo numero inconveniente invece della lettera fornitoci da Sigi	
--Scrittura nuova tabella YSR
--------------------------------------------------------------------

--------------------------------------------------------------------
-- Cocco Bill 20210427 -- Evolutiva SR Backlog
--                   20210707 -- Evolutiva SR Backlog fase 2 cambio stati
--
-- Nuova la logica di aggiornamento stato SR per elaborazione stati SR Backlog diversi da '21'
-- Nuove logiche sostituzione SR stato 29 e stato SM rettificati per "Backlog Fase 2"
--------------------------------------------------------------------

CREATE  PROCEDURE [dbo].[sp_test_001] AS
SET NOCOUNT ON

-- ESEGUE I FILTRI DALLE TABELLE DI STAGING KWTA1, KWTA2, KWTA4
DECLARE @esitofiltri INT
EXEC @ESITOFILTRI = [dbo].[spKImportSRApplyFilters]

IF @esitofiltri > 0

BEGIN

	DECLARE @wta1GUID 			nvarchar(38)--uniqueidentifier
	DECLARE @wta2GUID 			nvarchar(38)--uniqueidentifier
	DECLARE @CurrentDate 		smalldatetime
	DECLARE @IDSR 				int
	DECLARE @IDSRD 				int
	DECLARE @StatoSR 			int
	DECLARE @StatoPending 		int
	DECLARE @StatoPrenotabile 	int
	DECLARE @StatoAnnullato 	int  -- CCB 20210722 SR Backlog
	DECLARE @last_error		 	int

	DECLARE @Messaggio          nvarchar(max)
	DECLARE @ScriviLog          bit = 1
	DECLARE @NomeSP             nvarchar(50) = 'spKImportSR'

	DECLARE	@IDSR_Sostituita    int   -- 20210707 -- Cocco Bill - Evolutiva SR Backlog fase 2 -
	                                  --             Per la ricerca delle SR 29 sostituite da una SR in fase di import
    DECLARE	@Ricicla_Codice_SM  Bit   --             Flag per eventuale "riciclo" dei codici SM da SR annullata in precedenza
	DECLARE @IDSM_Riciclata		int   --             Cocide SM riciclato dalla precedente SM stato 29

	SET @CurrentDate = GETDATE()
	--SELECT @StatoPending = IDStatoSM FROM AStatoSM WHERE CodStatoSM = '000'
	SET @StatoPending = 9 
	--SELECT @StatoPrenotabile = IDStatoSM FROM AStatoSM WHERE CodStatoSM = '999'
	SET @StatoPrenotabile = 10
	SET @StatoAnnullato = 95 -- CCB 20210722 - SR Backlog - "095 - Annullato Sigi"

	DECLARE @minSmallDateTime nvarchar(8)
	DECLARE @maxSmallDateTime nvarchar(8)
	set @minSmallDateTime = '19000101'
	set @maxSmallDateTime = '20790606'
	
	--to do: attenzione che "trappiamo" lo smalldatetime ma non il datetime
	--vedi il cast to datetime nei vari case
	--la soluzinoe da applicare a tutti ic ase è:
	--WHEN ( DATAINIZIOGARANZIA = '00000000' OR cast(datainiziogaranzia as INT) < '17530101' ) THEN NULL
	--dove 1753 è il valore minimo di datetime

	-- BEGIN: Cursor on KWTA1
	DECLARE @NUMEROSR					nvarchar(6)
	DECLARE @MERCATO					nvarchar(4)
	DECLARE @SOCIETA					nvarchar(2)
	DECLARE @DIVISIONE					nvarchar(2)
	DECLARE @DIREAZIONEAREA				nvarchar(2)
	DECLARE @MARCA						nvarchar(2)
	DECLARE @ENTEEMITTENTE				nvarchar(7)
	DECLARE @CODICERIPARATORE			nvarchar(7)
	DECLARE @CODICEMVS					nvarchar(7)
	DECLARE @DATAEMISSIONE				nvarchar(6)
	DECLARE @TELAIO						nvarchar(8)
	DECLARE @DATAINIZIOGARANZIA			nvarchar(8)
	DECLARE @KMVETTURA					nvarchar(6)
	DECLARE @DATAINTERVENTO				nvarchar(8)
	DECLARE @NUMERORICEVUTAFISCALE		nvarchar(11)
	DECLARE @DATARICEVUTAFISCALE		nvarchar(8)
	DECLARE @NUMEROCOMMESSA				nvarchar(6)
	DECLARE @DATACHIUSURACOMMESSA 		nvarchar(8)
	DECLARE @DATACONTABILIZZAZIONE 		nvarchar(8)
	DECLARE @TOTALEOREMO				nvarchar(4)
	DECLARE @SR_SEGNOIMPORTOMO			nvarchar(1)
	DECLARE @SR_IMPORTOMO				nvarchar(12)
	DECLARE @SR_SEGNOIMPORTOMATERIALI	nvarchar(1)
	DECLARE @SR_IMPORTOMATERIALI		nvarchar(12)
	DECLARE @SEGNOIMPORTOTOTALESR		nvarchar(1)
	DECLARE @IMPORTOTOTALESR			nvarchar(12)
	DECLARE @DATAPRODUZIONEVEICOLO		nvarchar(8)

	SET @Messaggio = ' === Inizio esecuzione Import SR SIGI - Ora di partenza: '   + convert(varchar, getdate(), 126) + ' ==='
	PRINT @Messaggio
	If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

	DECLARE WTA1_Cursor CURSOR FOR
	SELECT [ID], STATOSR, NUMEROSR, MERCATO, SOCIETA, DIVISIONE, DIREAZIONEAREA, MARCA, ENTEEMITTENTE, CODICERIPARATORE, 
		CODICEMVS, DATAEMISSIONE, TELAIO, DATAINIZIOGARANZIA, KMVETTURA, DATAINTERVENTO, NUMERORICEVUTAFISCALE, DATARICEVUTAFISCALE, 
		NUMEROCOMMESSA, DATACHIUSURACOMMESSA, DATACONTABILIZZAZIONE, TOTALEOREMO, SEGNOIMPORTOMO, IMPORTOMO, SEGNOIMPORTOMATERIALI, 
		IMPORTOMATERIALI, SEGNOIMPORTOTOTALESR, IMPORTOTOTALESR, DATAPRODUZIONEVEICOLO
	FROM KWTA1
	--WHERE STATOSR = '21' 

	OPEN WTA1_Cursor

	FETCH NEXT FROM WTA1_Cursor
	INTO @wta1GUID, @StatoSR, @NUMEROSR, @MERCATO, @SOCIETA, @DIVISIONE, @DIREAZIONEAREA, @MARCA, @ENTEEMITTENTE, @CODICERIPARATORE, 
		@CODICEMVS, @DATAEMISSIONE, @TELAIO, @DATAINIZIOGARANZIA, @KMVETTURA, @DATAINTERVENTO, @NUMERORICEVUTAFISCALE, @DATARICEVUTAFISCALE, 
		@NUMEROCOMMESSA, @DATACHIUSURACOMMESSA, @DATACONTABILIZZAZIONE, @TOTALEOREMO, @SR_SEGNOIMPORTOMO, @SR_IMPORTOMO, @SR_SEGNOIMPORTOMATERIALI, 
		@SR_IMPORTOMATERIALI, @SEGNOIMPORTOTOTALESR, @IMPORTOTOTALESR, @DATAPRODUZIONEVEICOLO

	WHILE @@FETCH_STATUS = 0
	BEGIN
	    
		DECLARE @IDEnteEmittente	int
		DECLARE @IDEnteRiparatore	int
		DECLARE @IDStato			int

		SET @IDEnteEmittente = NULL
		SET @IDEnteRiparatore = NULL

		SELECT @IDEnteEmittente = IDEnte FROM AEnti WHERE CodMercato = @MERCATO AND CodMarca = @MARCA AND CodEnte = @ENTEEMITTENTE 
		SELECT @IDEnteRiparatore = IDEnte FROM AEnti WHERE CodMercato = @MERCATO AND CodMarca = @MARCA AND CodEnte = @CODICERIPARATORE

		IF @IDEnteRiparatore IS NULL
			SET @IDEnteRiparatore = @IDEnteEmittente
			
		-- Cocco Bill 20210708 - Fix durante i test SR Backlog. 
		-- Se non esiste l'anagrafica Enti il valore NULL in @IDEnteEmittente fa fallire la select
		-- di esistenza della SR e provoca l'inserimento di una nuova IDSR con gli stessi dati senza codice Dealer Emittente
		-- Intercetto l'errore e salto il KWTA1 e segmenti dipendenti.

		IF @IDEnteEmittente IS NULL
		Begin
			SET @Messaggio = 'Anomalia Anagrafica Ente Emitttente non trovata su AEnti per  SR - numero SR: ' + dbo.fnIsNull(@NUMEROSR) + ' Mercato: ' + dbo.fnIsNull(@MERCATO) + ' Marca: ' + dbo.fnIsNull(@MARCA) +
				' Codice Ente: ' + dbo.fnIsNull(@ENTEEMITTENTE) +' Anno Emissione: ' + dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 1, 4))
				+ ' Mese Emissione: ' + dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 5, 2)) + ' SR esclusa dall''import! '
			--PRINT @Messaggio
			EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 0
			Goto Next_Wta1
		End

		-- Cocco Bill 20210708 - Fine della Fix

		/*****************************************************************************/
		/* Importazione delle testate SR											 */
		/*****************************************************************************/
	--	BEGIN TRANSACTION insert_wta1

	--	IF dbo.isReallyInt(dbo.fnIsNull(@DATAINIZIOGARANZIA)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@DATAINTERVENTO)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@DATARICEVUTAFISCALE)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@DATACHIUSURACOMMESSA)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@DATACONTABILIZZAZIONE)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@SR_IMPORTOMO)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@SR_IMPORTOMATERIALI)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@IMPORTOTOTALESR)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@TOTALEOREMO)) = 0
	--		OR dbo.isReallyInt(dbo.fnIsNull(@KMVETTURA)) = 0
	--	BEGIN
	--		SET @last_error = -1
	--		GOTO error_wta1
	--	END

		/**********************************************************************************************/
		/* CONTROLLO ESISTENZA CHIAVE SR */
		/**********************************************************************************************/

		DECLARE @EsisteSR INT

		SELECT @EsisteSR = COUNT(*)
		FROM ASR
		WHERE 
			IDMercato = dbo.fnIsNull(@MERCATO) AND
			IDMarca = dbo.fnIsNull(@MARCA) AND
			NumeroSR = dbo.fnIsNull(@NUMEROSR) AND
			IDEnteEmittente = @IDEnteEmittente AND
			AnnoEmissione = dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 1, 4)) AND
			MeseEmissione = dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 5, 2))

			--SET @Messaggio = 'Verifica esistenza SR - numero SR: ' + dbo.fnIsNull(@NUMEROSR) + ' Mercato: ' + dbo.fnIsNull(@MERCATO) + ' Marca: ' + dbo.fnIsNull(@MARCA) +
			--			' Codice Ente: ' + dbo.fnIsNull(@ENTEEMITTENTE) +' Id Ente emittente: ' + STR(isnull(@IDEnteEmittente, 0)) + ' Anno Emissione: ' + dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 1, 4))
			--			+ ' Mese Emissione: ' + dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 5, 2)) + ' Risultato: ' + str(@EsisteSR)
			--PRINT @Messaggio
			--If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

		IF @EsisteSR = 0
		BEGIN
			INSERT INTO ASR (NumeroSR, IDMercato, CodSocieta, CodDivisione, DirezioneArea, IDMarca, IDEnteEmittente, IDEnteRiparatore, CodModello, CodVersione, CodSerie, AnnoEmissione, 
				MeseEmissione, DataInvio, Telaio, IDStato, DataInizioGaranzia, KMVettura, DataIntervento, NumeroRicFisc, DataRicFisc, NumCommessa, DataChCommessa, 
				DataContabilizzazione, TotaleMonteOre, ImportoMonteOre, ImportoMateriali, ImportoTotale, DataProduzioneVeicolo )
			VALUES(
				dbo.fnIsNull(@NUMEROSR), 
				dbo.fnIsNull(@MERCATO),
				dbo.fnIsNull(@SOCIETA),
				dbo.fnIsNull(@DIVISIONE),
				dbo.fnIsNull(@DIREAZIONEAREA),
				dbo.fnIsNull(@MARCA),
				@IDEnteEmittente,	--dbo.fnIsNull(@ENTEEMITTENTE),
				@IDEnteRiparatore,	--dbo.fnIsNull(@CODICERIPARATORE),
				dbo.fnIsNull(SUBSTRING(@CODICEMVS, 1, 3)),
				dbo.fnIsNull(SUBSTRING(@CODICEMVS, 4, 3)),
				dbo.fnIsNull(SUBSTRING(@CODICEMVS, 7, 1)),
				dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 1, 4)),
				dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 5, 2)),
				@CurrentDate, --Data Invio (il default è la data di importazione)
				dbo.fnIsNull(@TELAIO),
				dbo.fnIsNull(@STATOSR),
				CASE 
					WHEN ( @DATAINIZIOGARANZIA = '00000000') THEN NULL
					WHEN CAST(@DATAINIZIOGARANZIA AS DATETIME) < @minSmallDateTime THEN @minSmallDateTime
					WHEN CAST(@DATAINIZIOGARANZIA AS DATETIME) > @maxSmallDateTime THEN @maxSmallDateTime
					ELSE CONVERT(smalldatetime, dbo.fnIsNull(@DATAINIZIOGARANZIA), 112)
				END,
				CONVERT(int, dbo.fnIsNull(@KMVETTURA)),
				CASE 
					WHEN (@DATAINTERVENTO = '00000000') THEN NULL
					WHEN CAST(@DATAINTERVENTO AS DATETIME) < @minSmallDateTime THEN @minSmallDateTime
					WHEN CAST(@DATAINTERVENTO AS DATETIME) > @maxSmallDateTime THEN @maxSmallDateTime
					ELSE CONVERT(smalldatetime, dbo.fnIsNull(@DATAINTERVENTO), 112)
				END,
				dbo.fnIsNull(@NUMERORICEVUTAFISCALE),
				CASE  
					WHEN (@DATARICEVUTAFISCALE = '00000000') THEN NULL
					WHEN CAST(@DATARICEVUTAFISCALE AS DATETIME) < @minSmallDateTime THEN @minSmallDateTime
					WHEN CAST(@DATARICEVUTAFISCALE AS DATETIME) > @maxSmallDateTime THEN @maxSmallDateTime
					ELSE CONVERT(smalldatetime, dbo.fnIsNull(@DATARICEVUTAFISCALE), 112)
				END,
				dbo.fnIsNull(@NUMEROCOMMESSA),
				CASE 
					WHEN (@DATACHIUSURACOMMESSA = '00000000') THEN NULL
					WHEN CAST(@DATACHIUSURACOMMESSA AS DATETIME) < @minSmallDateTime THEN @minSmallDateTime
					WHEN CAST(@DATACHIUSURACOMMESSA AS DATETIME) > @maxSmallDateTime THEN @maxSmallDateTime
					ELSE CONVERT(smalldatetime, dbo.fnIsNull(@DATACHIUSURACOMMESSA), 112)
				END,
				CASE 
					WHEN (@DATACONTABILIZZAZIONE = '00000000') THEN NULL
					WHEN CAST(@DATACONTABILIZZAZIONE AS DATETIME) < @minSmallDateTime THEN @minSmallDateTime
					WHEN CAST(@DATACONTABILIZZAZIONE AS DATETIME) > @maxSmallDateTime THEN @maxSmallDateTime
					ELSE CONVERT(smalldatetime, dbo.fnIsNull(@DATACONTABILIZZAZIONE), 112)
				END,
				CAST(@TOTALEOREMO AS decimal(6, 2)) / 100,
				CAST(
					CASE 
						WHEN @SR_SEGNOIMPORTOMO = '+' THEN CAST(dbo.fnIsNull(@SR_IMPORTOMO) AS decimal(15, 3)) / 1000
						WHEN @SR_SEGNOIMPORTOMO = '-' THEN CAST(dbo.fnIsNull(@SR_IMPORTOMO) AS decimal(15, 3)) / 1000 * (-1)
					END
				AS decimal(12, 3)),
				CAST(
					CASE 
						WHEN @SR_SEGNOIMPORTOMATERIALI = '+' THEN CAST(dbo.fnIsNull(@SR_IMPORTOMATERIALI) AS decimal(15, 3)) / 1000
						WHEN @SR_SEGNOIMPORTOMATERIALI = '-' THEN CAST(dbo.fnIsNull(@SR_IMPORTOMATERIALI) AS decimal(15, 3)) / 1000 * (-1)
					END
				AS decimal(12, 3)),
				CAST(
					CASE 
						WHEN @SEGNOIMPORTOTOTALESR = '+' THEN CAST(dbo.fnIsNull(@IMPORTOTOTALESR) AS decimal(15, 3)) / 1000
						WHEN @SEGNOIMPORTOTOTALESR = '-' THEN CAST(dbo.fnIsNull(@IMPORTOTOTALESR) AS decimal(15, 3)) / 1000 * (-1)
					END
				AS decimal(12, 3)),
				CASE 
					WHEN (@DATAPRODUZIONEVEICOLO = '00000000') THEN NULL
					WHEN CAST(@DATAPRODUZIONEVEICOLO AS DATETIME) < @minSmallDateTime THEN @minSmallDateTime
					WHEN CAST(@DATAPRODUZIONEVEICOLO AS DATETIME) > @maxSmallDateTime THEN @maxSmallDateTime
					ELSE CONVERT(smalldatetime, dbo.fnIsNull(@DATAPRODUZIONEVEICOLO), 112)
				END
			)	

		--	SET @last_error = @@ERROR
			
			SET @IDSR = SCOPE_IDENTITY()

		--	IF @last_error > 0
		--	BEGIN
		--error_wta1:
		--		ROLLBACK TRANSACTION insert_wta1
		--
		--		INSERT INTO [KWTA1Scratch]
		--			([ERROR],[ID],[TIPO],[MERCATO],[SOCIETA],[DIVISIONE],[MARCA],[ENTEEMITTENTE],[NUMEROSR],[DATAEMISSIONE],[LETTERAINCONVENIENTE],
		--			[IDDOCUMENTO],[RIGAPROGRESSIVA],[TIPOSUDDIVISIONE],[DIREAZIONEAREA],[CODICECSM],[STATOSR],[CODICESPESA],
		--			[CODICEASSISTENZA],[NUMEROBLOCCO],[DATARICEZIONE],[CODICERIPARATORE],[CODICEVENDITORE],[CODICEMVS],[TELAIO],
		--			[DATAINIZIOGARANZIA],[KMVETTURA],[DATAINTERVENTO],[NUMERORICEVUTAFISCALE],[DATARICEVUTAFISCALE],[NUMEROCOMMESSA],
		--			[DATACHIUSURACOMMESSA],[DATACONTABILIZZAZIONE],[TOTALEOREMO],[SEGNOIMPORTOMO],[IMPORTOMO],[SEGNOLAVORITERZI],
		--			[IMPORTOLAVORITERZI],[SEGNOIMPORTOMATERIALI],[IMPORTOMATERIALI],[SEGNOIMPORTOTOTALESR],[IMPORTOTOTALESR],
		--			[SEGNOIMPORTOACQUISTILOCALI],[IMPORTOACQUISTILOCALI],[FILLER],[CODICEIMPORTATORE],[FILLER2],[NUMEROINVIO])
		--		SELECT 
		--			@last_error,[ID],[TIPO],[MERCATO],[SOCIETA],[DIVISIONE],[MARCA],[ENTEEMITTENTE],[NUMEROSR],[DATAEMISSIONE],[LETTERAINCONVENIENTE],
		--			[IDDOCUMENTO],[RIGAPROGRESSIVA],[TIPOSUDDIVISIONE],[DIREAZIONEAREA],[CODICECSM],[STATOSR],[CODICESPESA],
		--			[CODICEASSISTENZA],[NUMEROBLOCCO],[DATARICEZIONE],[CODICERIPARATORE],[CODICEVENDITORE],[CODICEMVS],[TELAIO],
		--			[DATAINIZIOGARANZIA],[KMVETTURA],[DATAINTERVENTO],[NUMERORICEVUTAFISCALE],[DATARICEVUTAFISCALE],[NUMEROCOMMESSA],
		--			[DATACHIUSURACOMMESSA],[DATACONTABILIZZAZIONE],[TOTALEOREMO],[SEGNOIMPORTOMO],[IMPORTOMO],[SEGNOLAVORITERZI],
		--			[IMPORTOLAVORITERZI],[SEGNOIMPORTOMATERIALI],[IMPORTOMATERIALI],[SEGNOIMPORTOTOTALESR],[IMPORTOTOTALESR],
		--			[SEGNOIMPORTOACQUISTILOCALI],[IMPORTOACQUISTILOCALI],[FILLER],[CODICEIMPORTATORE],[FILLER2],[NUMEROINVIO]
		--		FROM [KWTA1]
		--		WHERE [ID] = @wta1GUID
		--
		--		GOTO next_wta1
		--	END

			-- BEGIN: Cursor on KWTA2
			DECLARE @CODICESPESA						nvarchar(3)
			DECLARE @CODICEPEZZO						nvarchar(8)
			DECLARE @CODICEANOMALIA						nvarchar(2)
			DECLARE @NUMEROAUTORIZZAZIONE				nvarchar(6)
			DECLARE @DESCRIZIONEMANIFESTAZIONEGUASTO	nvarchar(50)
			DECLARE @REVISIONESOSTITUZIONEMATERIALI		nvarchar(1)
			DECLARE @DEMERITO							nvarchar(1)
			DECLARE @FERMOVEICOLO						nvarchar(1)
			DECLARE @NUMEROCAMPAGNA						nvarchar(4)
			DECLARE @CODICEPOSIZIONE					nvarchar(15)
			DECLARE @LETTERAINCONVENIENTE				nvarchar(1)
			DECLARE @OREMO								nvarchar(4)
			DECLARE @SEGNOIMPORTOMO						nvarchar(1)
			DECLARE @IMPORTOMO							nvarchar(12)
			DECLARE @SEGNOIMPORTOMATERIALI				nvarchar(1)
			DECLARE @IMPORTOMATERIALI					nvarchar(12)
			DECLARE @SEGNOIMPORTOACQUISTILOCALI			nvarchar(1)
			DECLARE @IMPORTOACQUISTILOCALI				nvarchar(12)
			DECLARE @SEGNOIMPORTOLAVORITERZI			nvarchar(1)
			DECLARE @IMPORTOLAVORITERZI					nvarchar(12)

			--LP - 20160405 - Problema Posizionale - Scrittura nuova tabella YSR
			DECLARE @PROGRESSIVOINCRMPR					nvarchar(2)

			DECLARE WTA2_Cursor CURSOR FOR
			SELECT [ID], CODICESPESA, CODICEPEZZO, CODICEANOMALIA, NUMEROAUTORIZZAZIONE, DESCRIZIONEMANIFESTAZIONEGUASTO, REVISIONESOSTITUZIONEMATERIALI, DEMERITO, NUMEROCAMPAGNA, 
				CODICEPOSIZIONE, LETTERAINCONVENIENTE, OREMO, SEGNOIMPORTOMO, IMPORTOMO, SEGNOIMPORTOMATERIALI, IMPORTOMATERIALI, SEGNOIMPORTOACQUISTILOCALI, IMPORTOACQUISTILOCALI, 
				SEGNOLAVORITERZI, IMPORTOLAVORITERZI, FERMOVEICOLO, 
				--LP - 20160405 - Problema Posizionale - Scrittura nuova tabella YSR
				PROGRESSIVOINCRMPR
			FROM KWTA2 WHERE PARENTID = @wta1GUID
			
			OPEN WTA2_Cursor
			
			FETCH NEXT FROM WTA2_Cursor
			INTO @wta2GUID, @CODICESPESA, @CODICEPEZZO, @CODICEANOMALIA, @NUMEROAUTORIZZAZIONE, @DESCRIZIONEMANIFESTAZIONEGUASTO, @REVISIONESOSTITUZIONEMATERIALI, @DEMERITO, 
				@NUMEROCAMPAGNA, @CODICEPOSIZIONE, @LETTERAINCONVENIENTE, @OREMO, @SEGNOIMPORTOMO, @IMPORTOMO, @SEGNOIMPORTOMATERIALI, @IMPORTOMATERIALI, @SEGNOIMPORTOACQUISTILOCALI,
				@IMPORTOACQUISTILOCALI, @SEGNOIMPORTOLAVORITERZI, @IMPORTOLAVORITERZI, @FERMOVEICOLO, 
				--LP - 20160405 - Problema Posizionale - Scrittura nuova tabella YSR
				@PROGRESSIVOINCRMPR

			WHILE @@FETCH_STATUS = 0
			BEGIN
				/*****************************************************************************/
				/* Importazione delle SRDettaglio											 */
				/*****************************************************************************/
		--		IF dbo.isReallyInt(dbo.fnIsNull(@IMPORTOMO)) = 0
		--			OR dbo.isReallyInt(dbo.fnIsNull(@IMPORTOMATERIALI)) = 0
		--			OR dbo.isReallyInt(dbo.fnIsNull(@IMPORTOACQUISTILOCALI)) = 0
		--			OR dbo.isReallyInt(dbo.fnIsNull(@IMPORTOLAVORITERZI)) = 0
		--			OR dbo.isReallyInt(dbo.fnIsNull(@OREMO)) = 0
		--		BEGIN
		--			SET @last_error = -1
		--			GOTO error_wta2
		--		END

				INSERT INTO ASRDettaglio (IDSR, CodiceSpesa, CodCodiceInput, CodAnomalia, NumeroAut, DescrizioneGuasto, RevSostMateriali, FermoVeicolo, Demerito, 
					NumeroCampagna, CodPosizione, LetteraInconveniente, MonteOre, ImportoMonteOre, ImportoMateriali, ImportoAcquistiLocali, ImportoLavoriTerzi)
				VALUES (
					@IDSR,
					dbo.fnIsNull(@CODICESPESA),
					dbo.fnIsNull(@CODICEPEZZO),
					dbo.fnIsNull(@CODICEANOMALIA),
					dbo.fnIsNull(@NUMEROAUTORIZZAZIONE),
					dbo.fnIsNull(@DESCRIZIONEMANIFESTAZIONEGUASTO),
					CASE 
						WHEN dbo.fnIsNull(@REVISIONESOSTITUZIONEMATERIALI) IS NULL THEN 0
						WHEN dbo.fnIsNull(@REVISIONESOSTITUZIONEMATERIALI) = '0' THEN 0
						ELSE 1
					END,
					CASE 
						WHEN dbo.fnIsNull(@FERMOVEICOLO) IS NULL THEN 0
						WHEN dbo.fnIsNull(@FERMOVEICOLO) = '0' THEN 0
						ELSE 1
					END,
					CASE 
						WHEN dbo.fnIsNull(@DEMERITO) IS NULL THEN 0
						WHEN dbo.fnIsNull(@DEMERITO) = '0' THEN 0
						ELSE 1
					END,
					dbo.fnIsNull(@NUMEROCAMPAGNA),
					dbo.fnIsNull(@CODICEPOSIZIONE),
					dbo.fnIsNull(@LETTERAINCONVENIENTE),
					CAST(dbo.fnIsNull(@OREMO) AS decimal(6, 2)) / 100,
					CAST(
						CASE 
							WHEN @SEGNOIMPORTOMO = '+' THEN CAST(dbo.fnIsNull(@IMPORTOMO) AS decimal(15, 3)) / 1000
							WHEN @SEGNOIMPORTOMO = '-' THEN CAST(dbo.fnIsNull(@IMPORTOMO) AS decimal(15, 3)) / 1000 * (-1)
						END
					AS decimal(12, 3)),
					CAST(
						CASE 
							WHEN @SEGNOIMPORTOMATERIALI = '+' THEN CAST(dbo.fnIsNull(@IMPORTOMATERIALI) AS decimal(15, 3)) / 1000
							WHEN @SEGNOIMPORTOMATERIALI = '-' THEN CAST(dbo.fnIsNull(@IMPORTOMATERIALI) AS decimal(15, 3)) / 1000 * (-1)
						END
					AS decimal(12, 3)),
					CAST(
						CASE 
							WHEN @SEGNOIMPORTOACQUISTILOCALI = '+' THEN CAST(dbo.fnIsNull(@IMPORTOACQUISTILOCALI) AS decimal(15, 3)) / 1000
							WHEN @SEGNOIMPORTOACQUISTILOCALI = '-' THEN CAST(dbo.fnIsNull(@IMPORTOACQUISTILOCALI) AS decimal(15, 3)) / 1000 * (-1)
						END
					AS decimal(12, 3)),
					CAST(
						CASE 
							WHEN @SEGNOIMPORTOLAVORITERZI = '+' THEN CAST(dbo.fnIsNull(@IMPORTOLAVORITERZI) AS decimal(15, 3)) / 1000
							WHEN @SEGNOIMPORTOLAVORITERZI = '-' THEN CAST(dbo.fnIsNull(@IMPORTOLAVORITERZI) AS decimal(15, 3)) / 1000 * (-1)
						END
					AS decimal(12, 3))
				)

		--		SET @last_error = @@ERROR
				
				SET @IDSRD = SCOPE_IDENTITY()

		--		IF @last_error > 0
		--		BEGIN
		--error_wta2:
		--			ROLLBACK TRANSACTION insert_wta1
		--
		--			INSERT INTO [KWTA2Scratch]
		--				([ERROR],[ID],[PARENTID],[TIPO],[MERCATO],[SOCIETA],[DIVISIONE],[MARCA],[ENTEEMITTENTE],[NUMEROSR],[DATAEMISSIONE],
		--				[LETTERAINCONVENIENTE],[IDDOCUMENTO],[RIGAPROGRESSIVA],[TIPOSUDDIVISIONE],[DIREAZIONEAREA],[CODICECSM],[STATOSR],
		--				[CODICESPESA],[NUMEROAUTORIZZAZIONE],[DESCRIZIONEMANIFESTAZIONEGUASTO],[CODICEPEZZO],[CODICEPOSIZIONE],[CODICEANOMALIA],
		--				[FERMOVEICOLO],[DEMERITO],[REVISIONESOSTITUZIONEMATERIALI],[NUMEROCONTRATTO],[NUMEROCAMPAGNA],[LETTERAOPERAZIONE],
		--				[NUMERODISEGNOPEZZO],[DATAINSTALLAZIONE],[PERCASSRIC],[PERCASSPREC],[DATA],[SEGNOIMPORTOCARICOCLIENTE],[IMPORTOCARICOCLIENTE],
		--				[SEGNOIMPORTOMATERIALI],[IMPORTOMATERIALI],[SEGNOIMPORTOACQUISTILOCALI],[IMPORTOACQUISTILOCALI],[SEGNOLAVORITERZI],
		--				[IMPORTOLAVORITERZI],[OREMO],[SEGNOIMPORTOMO],[IMPORTOMO],[FILLER])
		--			SELECT 
		--				@last_error,[ID],[PARENTID],[TIPO],[MERCATO],[SOCIETA],[DIVISIONE],[MARCA],[ENTEEMITTENTE],[NUMEROSR],[DATAEMISSIONE],
		--				[LETTERAINCONVENIENTE],[IDDOCUMENTO],[RIGAPROGRESSIVA],[TIPOSUDDIVISIONE],[DIREAZIONEAREA],[CODICECSM],[STATOSR],
		--				[CODICESPESA],[NUMEROAUTORIZZAZIONE],[DESCRIZIONEMANIFESTAZIONEGUASTO],[CODICEPEZZO],[CODICEPOSIZIONE],[CODICEANOMALIA],
		--				[FERMOVEICOLO],[DEMERITO],[REVISIONESOSTITUZIONEMATERIALI],[NUMEROCONTRATTO],[NUMEROCAMPAGNA],[LETTERAOPERAZIONE],
		--				[NUMERODISEGNOPEZZO],[DATAINSTALLAZIONE],[PERCASSRIC],[PERCASSPREC],[DATA],[SEGNOIMPORTOCARICOCLIENTE],[IMPORTOCARICOCLIENTE],
		--				[SEGNOIMPORTOMATERIALI],[IMPORTOMATERIALI],[SEGNOIMPORTOACQUISTILOCALI],[IMPORTOACQUISTILOCALI],[SEGNOLAVORITERZI],
		--				[IMPORTOLAVORITERZI],[OREMO],[SEGNOIMPORTOMO],[IMPORTOMO],[FILLER]
		--			FROM KWTA2
		--			WHERE [ID] = @wta2GUID
		--
		--			GOTO next_wta2
		--		END

				/*****************************************************************************/
				/* Importazione delle SM													 */
				/*****************************************************************************/
		--		SELECT [ID] FROM KWTA4
		--		WHERE dbo.isReallyInt(dbo.fnIsNull(QUANTITA)) = 0 OR dbo.isReallyInt(dbo.fnIsNull(PREZZO)) = 0
		--
		--		IF @@ROWCOUNT > 0 
		--		BEGIN
		--			SET @last_error = -1
		--			GOTO error_wta4
		--		END


		-- CCB 20210715 -- Evolutiva SR Backlog Fase 2
		--                 Dalla insert massiva con "FROM  KWTA4W HERE PARENTID = @wta2GUID" passo alla 
		--                 versione con cursore per inserire uno ad uno gli IDSM e ottenere la loro SCOPE_IDENTITY()
		--                 In questo modo posso anche aggiornare la [dbo].[AsmExt] con le informazioni di 
		--                 lettera inconveniente e rigaprogressiva per rendere univoca la ricerca dei categorici 
		--                 che sono ripetuti all'interno della stessa SR / SRdettaglio in due o più posizioni differenti


/*   Versione originale insert immediata

				INSERT INTO ASM (
					IDSRDettaglio, 
					IDStato, 
					CodCategorico, 
					Quantita, 
					ResoGaranzia, 
					Prezzo, 
					CodOperativa,
					IDSR,
					IDEnteEmittente,
					IDRiparatore
				)
				SELECT 
					@IDSRD,

					CASE 
						WHEN @StatoSR = 21 THEN @StatoPending 	-- Stato [00 - PENDING]
						ELSE @StatoPrenotabile					-- Stato [99 - PRENOTABILE]
					END,
					dbo.fnIsNull(CODICERICAMBIO),
					CONVERT(int, dbo.fnIsNull(QUANTITA)),
					NULL,
					CASE 
						WHEN SEGNOPREZZO = '+' THEN CAST(dbo.fnIsNull(PREZZO) AS decimal(15, 3)) / 1000
						WHEN SEGNOPREZZO = '-' THEN CAST(dbo.fnIsNull(PREZZO) AS decimal(15, 3)) / 1000 * (-1)
					END,
					NULL,
					@IDSR,
					@IDEnteEmittente,
					@IDEnteRiparatore
				FROM  KWTA4
				WHERE PARENTID = @wta2GUID --AND (dbo.fnIsNull(CODICERETTIFICA) IS NULL AND dbo.fnIsNull(CODICEMOTIVAZIONE) IS NULL)
		--			AND dbo.isReallyInt(dbo.fnIsNull(QUANTITA)) = 1 AND dbo.isReallyInt(dbo.fnIsNull(PREZZO)) = 1
*/
 
            DECLARE @IDSM_WTA4				INT
			DECLARE @Stato_IDSM_WTA4		INT
			DECLARE @CODICERICAMBIO_WTA4    NVARCHAR(20) 
			DECLARE @QUANTITA_WTA4		    NVARCHAR(2) 
			DECLARE @PREZZO_WTA4			DECIMAL(15, 3) 
			DECLARE @LETTERAINCONVENIENTE_WTA4		NVARCHAR(1) 
			DECLARE @RIGAPROGRESSIVA_WTA4		    NVARCHAR(2) 
			DECLARE @CODICERETTIFICA_WTA4	NVARCHAR(2)
			DECLARE @CODICEMOTIVAZIONE_WTA4	NVARCHAR(2)

 			DECLARE WTA4_Cursor CURSOR FOR
				SELECT 
					CASE 
						WHEN @StatoSR = 21 THEN @StatoPending 	-- Stato [00 - PENDING]
						WHEN @StatoSR = 29 THEN @StatoAnnullato	-- Stato [95 - Annullato Sigi]  -- CCB 20210722 - SR Backlog 
						ELSE @StatoPrenotabile					-- Stato [99 - PRENOTABILE]
					END,
					dbo.fnIsNull(CODICERICAMBIO),
					CONVERT(int, dbo.fnIsNull(QUANTITA)),
					CASE 
						WHEN SEGNOPREZZO = '+' THEN CAST(dbo.fnIsNull(PREZZO) AS decimal(12, 3)) / 1000
						WHEN SEGNOPREZZO = '-' THEN CAST(dbo.fnIsNull(PREZZO) AS decimal(12, 3)) / 1000 * (-1)
					END,
					-- CCB 20210715 -- Evolutiva SR Backlog Fase 2
					--                 Leggo anche LETTERAINCONVENIENTE e RIGAPROGRESSIVA da WTA4)
					--                 [CODICERETTIFICA] e [CODICEMOTIVAZIONE] per variazione logica scrittura AmsRettifiche
					dbo.fnIsNull(LETTERAINCONVENIENTE),
					dbo.fnIsNull(RIGAPROGRESSIVA),
					dbo.fnIsNull([CODICERETTIFICA]),
					dbo.fnIsNull([CODICEMOTIVAZIONE])
				FROM  KWTA4
				WHERE PARENTID = @wta2GUID  
			
			OPEN WTA4_Cursor
			
			FETCH NEXT FROM WTA4_Cursor
			INTO @Stato_IDSM_WTA4, @CODICERICAMBIO_WTA4, @QUANTITA_WTA4, @PREZZO_WTA4, @LETTERAINCONVENIENTE_WTA4, @RIGAPROGRESSIVA_WTA4, @CODICERETTIFICA_WTA4, @CODICEMOTIVAZIONE_WTA4

			WHILE @@FETCH_STATUS = 0
			BEGIN

			    -- Import puntuale delle SM

				INSERT INTO ASM (
					IDSRDettaglio, 
					IDStato, 
					CodCategorico, 
					Quantita, 
					ResoGaranzia, 
					Prezzo, 
					CodOperativa,
					IDSR,
					IDEnteEmittente,
					IDRiparatore
				)
				
				VALUES (
					@IDSRD,
					@Stato_IDSM_WTA4,
					@CODICERICAMBIO_WTA4,
					@QUANTITA_WTA4,
					NULL,
					@PREZZO_WTA4,
					NULL,
					@IDSR,
					@IDEnteEmittente,
					@IDEnteRiparatore										
				)
				
				SET @IDSM_WTA4 = SCOPE_IDENTITY() --  <=== Id di ogni singola SM

				-- Con l'ID della SM appena creata aggiorno la [dbo].[AsmExt]

				INSERT INTO [dbo].[AsmExt]
						   ([IDSM]
						   ,[IDSR]
						   ,[IDSRDettaglio]
						   ,[CodCategorico]
						   ,[LETTERAINCONVENIENTE]
						   ,[RIGAPROGRESSIVA]
						   ,[DataUpdate]
						   ,[IDUserUpdate]
						   )
					 VALUES
						   (@idsm_wta4, -- <IDSM, int,>
						    @IDSR, -- <IDSR, int,>
						    @IDSRD, -- <IDSRDettaglio, int,>
						    @CODICERICAMBIO_WTA4, -- <CodCategorico, nvarchar(20),>
						    @LETTERAINCONVENIENTE_WTA4,--<LETTERAINCONVENIENTE, nvarchar(1),>
						    @RIGAPROGRESSIVA_WTA4, ---<RIGAPROGRESSIVA, nvarchar(2),>
							GETDATE(),
							0
							)

				FETCH NEXT FROM WTA4_Cursor
				INTO @Stato_IDSM_WTA4, @CODICERICAMBIO_WTA4, @QUANTITA_WTA4, @PREZZO_WTA4, @LETTERAINCONVENIENTE_WTA4, @RIGAPROGRESSIVA_WTA4, @CODICERETTIFICA_WTA4, @CODICEMOTIVAZIONE_WTA4

			END -- END: Cursor on KWTA4
			CLOSE WTA4_Cursor
			DEALLOCATE WTA4_Cursor


		--		SET @last_error = @@ERROR
		--		
		--		IF @last_error > 0
		--		BEGIN
		--error_wta4:
		--			ROLLBACK TRANSACTION insert_wta1
		--
		--			INSERT INTO [KWTA4Scratch]
		--				([ERROR],[ID],[PARENTID],[TIPO],[MERCATO],[SOCIETA],[DIVISIONE],[MARCA],[ENTEEMITTENTE],[NUMEROSR],[DATAEMISSIONE]
		--				,[LETTERAINCONVENIENTE],[IDDOCUMENTO],[RIGAPROGRESSIVA],[TIPOSUDDIVISIONE],[DIREAZIONEAREA],[CODICECSM],[STATOSR]
		--				,[CODICESPESA],[CODICERICAMBIO],[QUANTITA],[SEGNOPREZZO],[PREZZO],[SEGNOIMPORTOMATERIALE],[IMPORTOMATERIALE]
		--				,[SEGNOIMPORTOACQUISTILOCALI],[IMPORTOACQUISTILOCALI],[CODICERETTIFICA],[CODICEMOTIVAZIONE],[CODICEFORZATURA]
		--				,[DESCRIZIONERICAMBIO],[FILLER])
		--			SELECT
		--				@last_error,[ID],[PARENTID],[TIPO],[MERCATO],[SOCIETA],[DIVISIONE],[MARCA],[ENTEEMITTENTE],[NUMEROSR],[DATAEMISSIONE]
		--				,[LETTERAINCONVENIENTE],[IDDOCUMENTO],[RIGAPROGRESSIVA],[TIPOSUDDIVISIONE],[DIREAZIONEAREA],[CODICECSM],[STATOSR]
		--				,[CODICESPESA],[CODICERICAMBIO],[QUANTITA],[SEGNOPREZZO],[PREZZO],[SEGNOIMPORTOMATERIALE],[IMPORTOMATERIALE]
		--				,[SEGNOIMPORTOACQUISTILOCALI],[IMPORTOACQUISTILOCALI],[CODICERETTIFICA],[CODICEMOTIVAZIONE],[CODICEFORZATURA]
		--				,[DESCRIZIONERICAMBIO],[FILLER]
		--			FROM  KWTA4
		--			WHERE PARENTID = @wta2GUID AND (dbo.fnIsNull(CODICERETTIFICA) IS NULL AND dbo.fnIsNull(CODICEMOTIVAZIONE) IS NULL)
		--				AND (dbo.isReallyInt(dbo.fnIsNull(QUANTITA)) = 0 OR dbo.isReallyInt(dbo.fnIsNull(PREZZO)) = 0)
		--
		--			GOTO next_wta2
		--		END

			--LP - 20160405 - Problema Posizionale - Scrittura nuova tabella YSR
			if dbo.fnIsNull(@PROGRESSIVOINCRMPR) IS NOT NULL
			begin
				INSERT INTO YSR (IDSR, IDSRDettaglio, LetteraInconveniente, NumeroInconveniente)
				SELECT @IDSR, @IDSRD, dbo.fnIsNull(@LETTERAINCONVENIENTE), @PROGRESSIVOINCRMPR
			end

				-- CCB 20210427 -- Evolutiva SR Backlog
				--                 Aggiorno la [dbo].[ASMRettifiche] con le SM inserite per questa IDSR che su KWTA4
				--                 hanno CODICERETTIFICA / CODICEMOTIVAZIONE significativo per tenerne traccia 
				--                 ed escluderli dal job di cambio stati e addebito automatico.

				If NOT (dbo.fnIsNull(@CODICERETTIFICA_WTA4) IS NULL AND dbo.fnIsNull(@CODICEMOTIVAZIONE_WTA4) IS NULL)
					Begin
						INSERT INTO [dbo].[ASMRettifiche] (IDSM, CODICERETTIFICA, CODICEMOTIVAZIONE, [IDUserUpdate], [DataUpdate]) 
						VALUES(@IDSM_WTA4, @CODICERETTIFICA_WTA4, @CODICEMOTIVAZIONE_WTA4, 0, getdate())
					End
		

			/******  CCB 20210716 - Evolutiva SR Backlog Fase 2 - commento la vecchia logica usata prima del nuovo cursore WTA4

				DECLARE @CODRICAMBI TABLE(
					[CODICERICAMBIO]		nvarchar(020),
					[CODICERETTIFICA]		nvarchar(002),
					[CODICEMOTIVAZIONE]     nvarchar(002)
				)

				DECLARE @SM_RETTIFICATI TABLE(
					[IDSM]					int,
					[CODICERETTIFICA]		nvarchar(002),
					[CODICEMOTIVAZIONE]     nvarchar(002)
				)
				
				-- Ricreo la lista dei Categorici inseriti in ASM più sopra per il caso delle rettifiche attive

				DELETE FROM @CODRICAMBI;
				INSERT INTO @CODRICAMBI (CODICERICAMBIO, CODICERETTIFICA, CODICEMOTIVAZIONE) 
				SELECT dbo.fnIsNull(CODICERICAMBIO), dbo.fnIsNull(CODICERETTIFICA), dbo.fnIsNull(CODICEMOTIVAZIONE)
				  FROM KWTA4
			 	 WHERE PARENTID = @wta2GUID 
				   AND NOT (dbo.fnIsNull(CODICERETTIFICA) IS NULL AND dbo.fnIsNull(CODICEMOTIVAZIONE) IS NULL)
		
				-- Inserisce i nuovi SM rettificati nel log rettifiche. 
				-- L'Idsm lo trovo con categorico e chiave SR + SR Dettaglio + enti emittente + riparatore 

				INSERT INTO  @SM_RETTIFICATI (IDSM, CODICERETTIFICA, CODICEMOTIVAZIONE)
				SELECT ASM.IDSM, R.CODICERETTIFICA, R.CODICEMOTIVAZIONE
				  FROM ASM  
				INNER JOIN @CODRICAMBI R ON r.CODICERICAMBIO = ASM.CodCategorico
				WHERE ASM.IDSR            = @IDSR
				  AND ASM.IDSRDettaglio   = @IDSRD
				  AND ASM.IDEnteEmittente = @IDEnteEmittente
				  AND ASM.IDRiparatore    = @IDEnteRiparatore

				IF @@ROWCOUNT > 0 
				BEGIN
				    DECLARE @dbg_ricambio    nvarchar(020)
					DECLARE @dbg_rettifica   nvarchar(002) 
					DECLARE @dbg_motivazione nvarchar(002) 
					DECLARE debug_r_Cursor CURSOR FOR
						SELECT * FROM @CODRICAMBI 
					OPEN debug_r_Cursor
					FETCH NEXT FROM debug_r_Cursor INTO  @dbg_ricambio, @dbg_rettifica, @dbg_motivazione
					WHILE @@FETCH_STATUS = 0
					BEGIN
					    PRINT ' Debug rettifiche - categorico: ' + isnull(@dbg_ricambio,'-') + ' cod rett:' + isnull(@dbg_rettifica,'-')
						      + ' cod mot:' + isnull(@dbg_motivazione,'-') + ' idsr:' + STR(@IDSR) + ' idsr dettaglio:' + STR(@IDSRD)
						FETCH NEXT FROM debug_r_Cursor INTO  @dbg_ricambio, @dbg_rettifica, @dbg_motivazione
					END
					CLOSE debug_r_Cursor
			        DEALLOCATE debug_r_Cursor
				    PRINT ' Debug rettifiche - fine gruppo ----'
				END

				************** Fine CCB 20210716 - Evolutiva SR Backlog Fase 2 - commento la vecchia logica usata prima del nuovo cursore WTA4
				
				*/ 

				/*
				SELECT DISTINCT ASM.IDSM,  dbo.fnIsNull(k4.CODICERETTIFICA), dbo.fnIsNull(k4.CODICEMOTIVAZIONE)
				FROM  ASM 
				INNER JOIN KWTA4 K4 
				   ON ASM.CodCategorico= dbo.fnIsNull(CODICERICAMBIO)
			   	  AND K4.PARENTID = @wta2GUID 
				  AND NOT (dbo.fnIsNull(k4.CODICERETTIFICA) IS NULL AND dbo.fnIsNull(k4.CODICEMOTIVAZIONE) IS NULL)
				WHERE ASM.IDSR            = @IDSR
				  AND ASM.IDSRDettaglio   = @IDSRD
				  AND ASM.IDEnteEmittente = @IDEnteEmittente
				  AND ASM.IDRiparatore    = @IDEnteRiparatore
				*/
				-- CCB 20210427 -- Evolutiva SR Backlog -- Fine					

				FETCH NEXT FROM WTA2_Cursor
				INTO @wta2GUID, @CODICESPESA, @CODICEPEZZO, @CODICEANOMALIA, @NUMEROAUTORIZZAZIONE, @DESCRIZIONEMANIFESTAZIONEGUASTO, @REVISIONESOSTITUZIONEMATERIALI, @DEMERITO, 
					@NUMEROCAMPAGNA, @CODICEPOSIZIONE, @LETTERAINCONVENIENTE, @OREMO, @SEGNOIMPORTOMO, @IMPORTOMO, @SEGNOIMPORTOMATERIALI, @IMPORTOMATERIALI, @SEGNOIMPORTOACQUISTILOCALI,
					@IMPORTOACQUISTILOCALI, @SEGNOIMPORTOLAVORITERZI, @IMPORTOLAVORITERZI, @FERMOVEICOLO,
					--20160405 - Scrittura nuova tabella YSR
					@PROGRESSIVOINCRMPR					
			END -- END: Cursor on KWTA2
		

	--next_wta2:
			CLOSE WTA2_Cursor
			DEALLOCATE WTA2_Cursor

		END -- Fine Begin ramo THEN Esistenza SR (SR non esistente, da creare)
		ELSE -- CCB 20210427 -- Evolutiva SR Backlog -- Ramo SR già esistente
		BEGIN

			--Print ' SR già esistente: mercato:' + dbo.fnIsNull(@MERCATO) + ' Marca:' + dbo.fnIsNull(@MARCA) + ' Numero SR:' + dbo.fnIsNull(@NUMEROSR) +
			--      ' Id Emittente:' + str(@IDEnteEmittente) + ' Anno/Mese: ' + dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 1, 4)) + ' / ' + dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 5, 2))
		    
			-- CCB 20210427 -- Evolutiva SR Backlog
			--                 Elaboro anche il ramo per le SR già esistenti controllando un eventuale cambio stato
			--                 ed eventuali variazioni dei materiali associati per tutte le SR in stato <> 21


			-- (1) Cambio Stato SR

			DECLARE @StatoAttualeSR int
			DECLARE @IdQuestaSR     int
			DECLARE @NumeroQuestaSR nvarchar(006)

			SELECT @StatoAttualeSR = IDStato, @IdQuestaSR = IDSR, @NumeroQuestaSR = [NumeroSR]
				FROM ASR
				WHERE 
				IDMercato = dbo.fnIsNull(@MERCATO) AND
				IDMarca   = dbo.fnIsNull(@MARCA) AND
				NumeroSR  = dbo.fnIsNull(@NUMEROSR) AND
				IDEnteEmittente = @IDEnteEmittente AND
				AnnoEmissione = dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 1, 4)) AND
				MeseEmissione = dbo.fnIsNull(SUBSTRING(@DATAEMISSIONE, 5, 2))

			IF @StatoAttualeSR <> 21 -- Lo stato '21 - Liquidata' è finale nel workflow, non considero ulteriori variazioni
			BEGIN

				-- (1) Cambio Stato SR

				IF dbo.fnIsNull(@STATOSR) <> @StatoAttualeSR -- Lo stato Sigi è diverso da quello già in DRS
					BEGIN
						UPDATE ASR SET IDStato = dbo.fnIsNull(@STATOSR)
						WHERE IDSR = @IdQuestaSR

						SET @Messaggio = 'Variato stato SR con id: ' + str(@IdQuestaSR) + ' da: ' + STR(@StatoAttualeSR) + ' a: ' + STR(dbo.fnIsNull(@STATOSR))
						PRINT @Messaggio
						If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

						-- @@@ Se la SR passa in stato 29 annulla gli idsm dipendenti (dove possibile)

						IF dbo.fnIsNull(@STATOSR) = 29
							BEGIN
								DECLARE @quanti_SM_Annullati int = 0 
							    UPDATE ASM  
								SET IDStato = @StatoAnnullato, IDUserUpdate = 0, DataUpdate = getdate()
								WHERE IDSR = @IdQuestaSR -- Dipendente da questa SR
							    AND ASM.IDStato <> @StatoAnnullato -- Non è ancora annullato
								AND ASM.IDSTato in (select idstatosm from [dbo].[fnGetStatiSMIniziali]())	-- Solo se non ancora presi in carico dal dealer
							
								SET @quanti_SM_Annullati = @@ROWCOUNT
								
							    SET @Messaggio = 'Annullate in stato 095 annullo Sigi: ' + str(isnull(@quanti_SM_Annullati,-1)) + ' SM per la SR con id: ' + str(@IdQuestaSR)  
								PRINT @Messaggio
								If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1
							
							END -- if su stato sr = 29

					END -- Fine ramo Then cambio stato SR @STATOSR <> @StatoAttualeSR
				--ELSE
				--	BEGIN
				--		DECLARE @Dummy int =0
						
				--	    SET @Messaggio = 'SR esistente in stato 21 non variata in stato - Id: ' + str(@IdQuestaSR) + ' numero SR: ' + @NumeroQuestaSR + ' stato attuale: ' + str(@StatoAttualeSR) + ' stato Sigi: ' + isnull(dbo.fnIsNull(@STATOSR),'-')
				--		PRINT @Messaggio
				--		If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1
 
				--	END
			
			END -- Fine Begin ramo THEN Stato SR corrente diverso da 21 per cambio stato
	
			-- (2) 20210707 -- Cocco Bill - Evolutiva SR Backlog fase 2 
			--                 Prima di inserire eventuali nuovi categorici / IDSM 
			--                 verifica se la SR corrente sostituisce una annullata in stato 29

			SET @IDSR_Sostituita = 0 
			If @StatoSR <> '29'  -- Non cerco la stessa SR già annullata...
				BEGIN
					SET @IDSR_Sostituita = [dbo].[fnCheckSrSostituita](dbo.fnIsNull(@MERCATO), dbo.fnIsNull(@MARCA), dbo.fnIsNull(@ENTEEMITTENTE), dbo.fnIsNull(@CODICEMVS), dbo.fnIsNull(@TELAIO), dbo.fnIsNull(@DATAINTERVENTO) )
					If @IDSR_Sostituita <> 0
						BEGIN
							SET @Messaggio = 'Ricerca Sostituzioni - SR in stato 29 id: ' + str(@IDSR_Sostituita) + ' sostituita da SR corrente: ' + isnull(@NUMEROSR,'-') + ' Mercato: ' + IsNull(@MERCATO,'-') + ' Marca: ' + IsNull(@MARCA,'-') + ' Cod Ente : ' + IsNull(@ENTEEMITTENTE,'-') + ' MVS: ' +  IsNull(@CODICEMVS,'-') + ' Telaio: ' + IsNull(@TELAIO,'-') + ' Data Intervento: ' + IsNull(@DATAINTERVENTO,'-') 
							PRINT @Messaggio
							If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1
						END

				END -- fine SR con stato <> 29
				
			-- (3) Ci sono nuovi categorici sulla SR? (Codice Rettifica I0)

			-- dichiaro con un prefisso "W_" i campi locali già dichiarati nel ramo di inserimento SR / SM per non 
			-- rischiare interferenze

			DECLARE @W_IDSR	int = @IdQuestaSR                     -- SR corrente in fase di analisi
			DECLARE	@W_IDEnteEmittente int = @IDEnteEmittente     -- già reperito da WTA1_Cursor
			DECLARE	@W_IDEnteRiparatore int = @IDEnteRiparatore   -- già reperito da WTA1_Cursor

			-- Campi per cursore da KWTA2 (SrDettaglio)
			DECLARE @W_CODICESPESA						nvarchar(3)
			DECLARE @W_CODICEPEZZO						nvarchar(8)
			DECLARE @W_CODICEANOMALIA					nvarchar(2)
			DECLARE @W_RIGAPROGRESSIVA					nvarchar(2)			
			DECLARE @W_LETTERAINCONVENIENTE_W2			nvarchar(1)   -- quella a livello di WTA2 per ricerca ASR Dettaglio
			DECLARE @W_LETTERAINCONVENIENTE_W4			nvarchar(1)   -- quella a livello di WTA4 per AsmExt
			DECLARE @W_PROGRESSIVOINCRMPR				nvarchar(2)
					
			-- Campi per cursore da KWTA4 (insert in ASM)

			DECLARE @W_CODICERICAMBIO					nvarchar(20)
			DECLARE @W_QUANTITA                         nvarchar(2)
			DECLARE @W_SEGNOPREZZO						nvarchar(1)
			DECLARE @W_PREZZO							nvarchar(2)
			DECLARE @W_CODICERETTIFICA					nvarchar(2)
			DECLARE @W_CODICEMOTIVAZIONE				nvarchar(2)

			-- 

			DECLARE	@W_IDSRD int  -- L'idsrDettaglio associata al materiale mancante

			-- Ciclo su un cursore KWTA1 / 2 / 4 unito dai parent-id dove però 
			-- mancano dei materiali su ASM per la SR corrente e con il categorico del cursore KWTA
			-- In questo caso vuol dire che devo creare un nuovo materiale in AsrDettaglio e ASM come nel caso insert.

			-- CCB 20210716 - Note sulla ricerca del categorico 

			--Variazione logica per nuovi materiali: l'assenza del categorico non funziona nel caso particolare di 
			--                più IDSR Dettaglio distinte nella stessa SR per *stesso codice Categorico* 
			--                In pratica il codice della parte appare in più "posizioni" sotto la stessa SR con quantità differenti
			--                e codici spesa differenti, la not exists non funzionerebbe.
			--                Soluzione: si controlla la posizione sulla nuova ASMExt che in fase di import memorizza anche
			--                           la lettera inconveniente e la riga progressiva

			DECLARE Nuovi_Materiali_Cursor CURSOR FOR
				SELECT 
						-- Campi AsrDettaglio da KWTA2
						K2.CODICESPESA, K2.CODICEPEZZO, K2.CODICEANOMALIA,				
						K2.LETTERAINCONVENIENTE as LETTERAINCONVENIENTE_K2, 						
						-- Campi per ASM da KWTA4
						K4.CODICERICAMBIO, K4.QUANTITA, K4.SEGNOPREZZO, K4.PREZZO, K4.CODICERETTIFICA, 
						K4.CODICEMOTIVAZIONE, K4.RIGAPROGRESSIVA, K4.LETTERAINCONVENIENTE as LETTERAINCONVENIENTE_K4
					FROM KWTA4 K4
					inner join KWTA2 K2 on k4.PARENTID = K2.ID
					inner join KWTA1 K1 on K2.PARENTID = K1.ID
					where K1.ID = @wta1GUID -- Sto analizzando il KWTA1 corrente
						-- CCB 20210713 - Variazione logica per nuovi materiali
						-- Manca un ASM per questa IDSR esistente e con il categorico (Codice Ricambio) del cursore da KWTA4
						-- AND NOT EXISTS (SELECT 0 from ASM A where A.idsr = @IdQuestaSR and A.CodCategorico = dbo.fnIsNull(K4.CODICERICAMBIO))
						-- Si  controlla anche la posizione ad AsmEXt
						AND NOT EXISTS (SELECT 0 from dbo.ASMExt A 
						                         where A.idsr = @IdQuestaSR 
													-- @@@ Legge Idsr Dettaglio dagli elementi di K2
													AND A.[IDSRDettaglio] = [dbo].[fnGetIDSRDettaglioSigi](@IdQuestaSR, K2.CODICESPESA, K2.CODICEPEZZO, K2.CODICEANOMALIA, K2.LETTERAINCONVENIENTE)
													AND A.[CodCategorico] = dbo.fnIsNull(K4.CODICERICAMBIO)
													AND a.[LetteraInconveniente] = dbo.fnIsNull(K4.LETTERAINCONVENIENTE) 
													AND a.[RigaProgressiva] = dbo.fnIsNull(k4.RIGAPROGRESSIVA)
										)
						AND K4.CODICERETTIFICA = 'I0' -- Nuovi inserimenti
			OPEN Nuovi_Materiali_Cursor
			
			FETCH NEXT FROM Nuovi_Materiali_Cursor
			INTO @W_CODICESPESA, @W_CODICEPEZZO, @W_CODICEANOMALIA, @W_LETTERAINCONVENIENTE_W2, 
				 @W_CODICERICAMBIO, @W_QUANTITA, @W_SEGNOPREZZO, @W_PREZZO, @W_CODICERETTIFICA, 
				 @W_CODICEMOTIVAZIONE, @W_RIGAPROGRESSIVA, @W_LETTERAINCONVENIENTE_W4

			WHILE @@FETCH_STATUS = 0
			BEGIN

				SET @Messaggio = 'Nuovo materiale con rettifica ''I0'' su SR variata:' + @W_CODICEPEZZO + ' idsr:' + str(@W_IDSR)
				PRINT @Messaggio
				If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

				--- @@@ Legge ASR Dettaglio esistente e la riutilizza

				SET @W_IDSRD = [dbo].[fnGetIDSRDettaglioSigi](@IdQuestaSR, @W_CODICESPESA, @W_CODICEPEZZO, @W_CODICEANOMALIA, @W_LETTERAINCONVENIENTE_W2)
													
				SET @Messaggio = 'Individuata ASR Dettaglio con id DRS: ' + str(@W_IDSRD) + ' per materiale mancante su SR variata: ' + str(@W_IDSR) + ' con ricerca per IdQuestaSR: ' + str(isnull(@IdQuestaSR,0)) + ' CODICESPESA: ' + isnull(@W_CODICESPESA,'-') + ' CODICEPEZZO: ' + isnull(@W_CODICEPEZZO,'-') + ' CODICEANOMALIA: ' + isnull(@W_CODICEANOMALIA,'-') + ' LETTERAINCONVENIENTE_W2: ' + isnull(@W_LETTERAINCONVENIENTE_W2,'-')
				PRINT @Messaggio
				If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

				-- 20210712 Cocco Bill - Evolutiva SR Backlog fase 2 
				--          Se la SR corrente sta **sostituendo** una annullata in stato 29 verifico se su quella annullata
				--          è associato lo stesso categorico. In questo caso non inserisco un nuovo ASM ma 'riciclo' 
				--          lo stesso codice variando l'associazione dalla precedente SR / SR Dettaglio annullata a questa nuova

				SET @Ricicla_Codice_SM = 0 
				SET @IDSM_Riciclata = 0

				If @IDSR_Sostituita <> 0 
					BEGIN
						SELECT @IDSM_Riciclata = isnull(IDSM,0)  FROM ASM WHERE IDSR = @IDSR_Sostituita and CodCategorico = dbo.fnIsNull(@W_CODICERICAMBIO)
						if @IDSM_Riciclata = 0 Set @Ricicla_Codice_SM = 0 Else SET @Ricicla_Codice_SM = 1
					END

				SET @Messaggio = ' Debug>>> Risultato @Ricicla_Codice_SM : ' + STR(@Ricicla_Codice_SM) + '  @IDSM_Riciclata: ' + str(isnull(@IDSM_Riciclata,-1)) +  ' ricerca per @IDSR_Sostituita: ' + STR(isnull(@IDSR_Sostituita,-1)) + ' @W_CODICERICAMBIO: ' + IsNull(@W_CODICERICAMBIO,'-') 
				PRINT @Messaggio
				If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1
					   
				If @Ricicla_Codice_SM = 0  -- 20210712 Cocco Bill - Evolutiva SR Backlog fase 2 

					BEGIN  -- Ramo della creazione di una nuova SM, nessuna sostituzione --> insert nuovo codice
							
						INSERT INTO ASM (
							IDSRDettaglio, 
							IDStato, 
							CodCategorico, 
							Quantita, 
							ResoGaranzia, 
							Prezzo, 
							CodOperativa,
							IDSR,
							IDEnteEmittente,
							IDRiparatore
						)
						SELECT 
							@W_IDSRD,

							CASE 
								WHEN @STATOSR = 21 THEN @StatoPending 	-- Stato [00 - PENDING]
								WHEN @STATOSR = 29 THEN @StatoAnnullato	-- Stato [95 - Annullato Sigi]  -- CCB 20210722 - SR Backlog 
								ELSE @StatoPrenotabile					-- Stato [99 - PRENOTABILE]
							END,
							dbo.fnIsNull(@W_CODICERICAMBIO),
							CONVERT(int, dbo.fnIsNull(@W_QUANTITA)),
							NULL,
							CASE 
								WHEN @W_SEGNOPREZZO = '+' THEN CAST(dbo.fnIsNull(@W_PREZZO) AS decimal(15, 3)) / 1000
								WHEN @W_SEGNOPREZZO = '-' THEN CAST(dbo.fnIsNull(@W_PREZZO) AS decimal(15, 3)) / 1000 * (-1)
							END,
							NULL,
							@W_IDSR,
							@W_IDEnteEmittente,
							@W_IDEnteRiparatore


						DECLARE @W_IDSM int  -- Nuova SM appena creata
						SET @W_IDSM = SCOPE_IDENTITY()

						SET @Messaggio = 'Creata ASM ' + str(isnull(@W_IDSM,0)) + ' per materiale mancante su SR variata: ' + str(@W_IDSR)
						PRINT @Messaggio
						If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

						-- @@@ Scrive ASMExt per il nuovo SM creato ora

						-- Con l'ID della SM appena creata aggiorno la [dbo].[AsmExt]

						INSERT INTO [dbo].[AsmExt]
							   ([IDSM]
							   ,[IDSR]
							   ,[IDSRDettaglio]
							   ,[CodCategorico]
							   ,[LETTERAINCONVENIENTE]
							   ,[RIGAPROGRESSIVA]
							   ,[DataUpdate]
							   ,[IDUserUpdate]
							   )
						 VALUES
							   (@W_IDSM,		-- <IDSM, int,>
								@W_IDSR,		-- <IDSR, int,>
								@W_IDSRD,		-- <IDSRDettaglio, int,>
								@W_CODICERICAMBIO,			--<CodCategorico, nvarchar(20),>
								@W_LETTERAINCONVENIENTE_W4,	--<LETTERAINCONVENIENTE, nvarchar(1),>
								@W_RIGAPROGRESSIVA,			--<RIGAPROGRESSIVA, nvarchar(2),>
								GETDATE(),
								0
								)

						-- @@@ Scrive ASMRettifiche per la I0 trattata
					  
						If NOT (dbo.fnIsNull(@W_CODICERETTIFICA) IS NULL AND dbo.fnIsNull(@W_CODICEMOTIVAZIONE) IS NULL)
							Begin
								INSERT INTO [dbo].[ASMRettifiche] (IDSM, CODICERETTIFICA, CODICEMOTIVAZIONE, [IDUserUpdate], [DataUpdate]) 
								VALUES(@W_IDSM, @W_CODICERETTIFICA, @W_CODICEMOTIVAZIONE, 0, getdate())
							End

					END  -- Fine Ramo THEN della If Sm Riciclata = 0  (nessun riciclo, nuova SM)
				ELSE
					BEGIN  -- Ramo del riciclo codice di SM già esistente

						UPDATE [dbo].[ASM]
	
							SET [IDSRDettaglio] = @W_IDSRD,  -- <== Nuova IDSR DEttaglio appena inserita
								[IDStato] = CASE 
												WHEN /*@W_StatoSR*/ 
												 	 @StatoSR = 21 THEN @StatoPending 	-- Stato [00 - PENDING]
												ELSE @StatoPrenotabile					-- Stato [99 - PRENOTABILE]
											END,
								[CodCategorico] = dbo.fnIsNull(@W_CODICERICAMBIO),
								[Quantita] = CONVERT(int, dbo.fnIsNull(@W_QUANTITA)),
								[ResoGaranzia] = NULL,
								[Prezzo] = CASE 
											WHEN @W_SEGNOPREZZO = '+' THEN CAST(dbo.fnIsNull(@W_PREZZO) AS decimal(15, 3)) / 1000
											WHEN @W_SEGNOPREZZO = '-' THEN CAST(dbo.fnIsNull(@W_PREZZO) AS decimal(15, 3)) / 1000 * (-1)
										END,
								[CodOperativa] = NULL,								  
								[IDUserUpdate] = 0,
								[DataUpdate] = getdate(),
								[IDSR] = @W_IDSR,  -- <==  IDSR corrente in fase di import
								[IDEnteEmittente] = @W_IDEnteEmittente,								  
								[IDRiparatore]    = @W_IDEnteRiparatore

							WHERE IDSM = @IDSM_Riciclata; --  <=== Aggiorna la SM già esistente associandola alla nuova SR / SR Dettaglio

							SET @Messaggio = 'Riciclato codice ASM esistente : ' + str(isnull(@IDSM_Riciclata,0)) + ' per materiale mancante su SR variata ' + str(@W_IDSR) +  ' in sostituzione della SR annullata: ' + str(isnull(@IDSR_Sostituita,0))
							PRINT @Messaggio
							If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

							-- @@@ Allinea ASMExt per l'SM riciclato

							DECLARE @EsisteASMExt INT

							SELECT @EsisteASMExt = COUNT(*)
							FROM ASMExt
							WHERE AsmExt.IDSM = @IDSM_Riciclata;

							IF @EsisteASMExt = 0
								BEGIN
									INSERT INTO [dbo].[AsmExt]
											   ([IDSM]
											   ,[IDSR]
											   ,[IDSRDettaglio]
											   ,[CodCategorico]
											   ,[LetteraInconveniente]
											   ,[RigaProgressiva]
											   ,[DataUpdate]
											   ,[IDUserUpdate]
											   )
										 VALUES
											   (@IDSM_Riciclata, -- <IDSM, int,>
											    @W_IDSR, -- <==  IDSR corrente in fase di import  ,<IDSR, int,>
											    @W_IDSRD,  -- <== Nuova IDSR DEttaglio appena inserita  ,<IDSRDettaglio, int,>
											    dbo.fnIsNull(@W_CODICERICAMBIO), -- <CodCategorico, nvarchar(20),>
											    @W_LETTERAINCONVENIENTE_W4,--	--<LETTERAINCONVENIENTE, nvarchar(1),>
												@W_RIGAPROGRESSIVA, -- ,<RigaProgressiva, nvarchar(2),>
												GETDATE(),
												0
											   )
								
								END
							ELSE
								BEGIN
									UPDATE [dbo].[AsmExt]
									   SET 
										  [IDSR] = @W_IDSR,				-- <==  IDSR corrente in fase di import  <IDSR, int,>
										  [IDSRDettaglio] = @W_IDSRD,	-- <== Nuova IDSR DEttaglio appena inserita <IDSRDettaglio, int,>
										  [CodCategorico] = dbo.fnIsNull(@W_CODICERICAMBIO),	-- <CodCategorico, nvarchar(20),>
										  [LetteraInconveniente] = @W_LETTERAINCONVENIENTE_W4,		-- <LetteraInconveniente, nvarchar(1),>
										  [RigaProgressiva] = @W_RIGAPROGRESSIVA,				--<RigaProgressiva, nvarchar(2),>
										  [DataUpdate] = GETDATE(),
										  [IDUserUpdate] = 0
									 WHERE ASMExt.IDSM = @IDSM_Riciclata
								END
								
					END  -- Fine Ramo ELSE della If Sm Riciclata = 0  (riciclo SM esistente)

						
				IF dbo.fnIsNull(@W_PROGRESSIVOINCRMPR) IS NOT NULL
				BEGIN
					INSERT INTO YSR (IDSR, IDSRDettaglio, LetteraInconveniente, NumeroInconveniente)
					SELECT @W_IDSR, @W_IDSRD, dbo.fnIsNull(@W_LETTERAINCONVENIENTE_W4), @W_PROGRESSIVOINCRMPR;
					Print 'Creato YSR per SR:' + str(@W_IDSR) + ' SR Dettaglio:' + str(@W_IDSRD) + ' lettera inc: ' + @W_LETTERAINCONVENIENTE_W4 + ' Prog Inc RMPR: ' + @W_PROGRESSIVOINCRMPR
				END

				FETCH NEXT FROM Nuovi_Materiali_Cursor						
							INTO @W_CODICESPESA, @W_CODICEPEZZO, @W_CODICEANOMALIA, @W_LETTERAINCONVENIENTE_W2, 

						  --      @W_NUMEROAUTORIZZAZIONE, @W_DESCRIZIONEMANIFESTAZIONEGUASTO, 
								--@W_REVISIONESOSTITUZIONEMATERIALI, @W_DEMERITO, @W_NUMEROCAMPAGNA, @W_CODICEPOSIZIONE, 
								--/*@W_LETTERAINCONVENIENTE,*/ @W_OREMO, @W_SEGNOIMPORTOMO, @W_IMPORTOMO, @W_SEGNOIMPORTOMATERIALI, 
								--@W_IMPORTOMATERIALI, @W_SEGNOIMPORTOACQUISTILOCALI, @W_IMPORTOACQUISTILOCALI, 
								--@W_SEGNOIMPORTOLAVORITERZI, @W_IMPORTOLAVORITERZI, 
								--@W_FERMOVEICOLO, @W_PROGRESSIVOINCRMPR,

								@W_CODICERICAMBIO, @W_QUANTITA, @W_SEGNOPREZZO, @W_PREZZO, @W_CODICERETTIFICA, @W_CODICEMOTIVAZIONE, @W_RIGAPROGRESSIVA, @W_LETTERAINCONVENIENTE_W4

			END

			CLOSE Nuovi_Materiali_Cursor
			DEALLOCATE Nuovi_Materiali_Cursor

			-- (4) Ci sono categorici con rettifica A0 da rendere "annullati" ?

			---@@@ Annullo A0

			DECLARE @ANN_CODICERICAMBIO			nvarchar(20) 
			DECLARE @ANN_CODICERETTIFICA		nvarchar(02) 
			DECLARE @ANN_CODICEMOTIVAZIONE		nvarchar(02) 
			DECLARE @ANN_LETTERAINCONVENIENTE	nvarchar(01) 
			DECLARE @ANN_RIGAPROGRESSIVA		nvarchar(02) 
			DECLARE @ANN_IDSR					Int
			DECLARE @ANN_IDSRDETTAGLIO			Int
			DECLARE @ANN_IDSM					Int
			DECLARE @ANN_IDSTATOSM				Int

			-- Controllo della ripetizione categorico nella SRDettaglio per discriminare la selezione con ASM o ASMExt

			DECLARE Materiali_Annullati_Cursor CURSOR FOR

			/* 
			    -- Questa versione del cursore utilizza SEMPRE la posizione che è un nuovo dato su DRS
				-- Dato che non è possibile recuperare il pregresso differenzio la logica di annullo
				-- e utilizzo la posizione su AsmExt *SOLO* quando il cateogorico è effettivamente
				-- ripetuto sotto la stessa identica IDSR / IDSDETTAGLIO su più posizioni

				-- Se questo non avviene le informazioni su ASM sono sufficienti per identificare l'IDSM

				SELECT 
						K4.CODICERICAMBIO, K4.CODICERETTIFICA, K4.CODICEMOTIVAZIONE,
						k4.LETTERAINCONVENIENTE, K4.RIGAPROGRESSIVA,
						ex.idsm, sm.idstato as statosm
					FROM KWTA4 K4
					inner join KWTA2 K2 on k4.PARENTID = K2.ID
					inner join KWTA1 K1 on K2.PARENTID = K1.ID
					LEFT JOIN AsmExt ex on ex.[CodCategorico]        = dbo.fnIsNull(k4.CODICERICAMBIO) 
										AND ex.IDSR = @IdQuestaSR
										AND ex.[LetteraInconveniente] = dbo.fnIsNull(K4.LETTERAINCONVENIENTE) 
										AND ex.[RigaProgressiva]      = dbo.fnIsNull(k4.RIGAPROGRESSIVA)
					LEFT JOIN ASM SM on SM.idsm = ex.IDSM
					WHERE 
						K1.ID = @wta1GUID -- Sto analizzando il KWTA1 corrente			
						AND K4.CODICERETTIFICA = 'A0' -- Annullo Sigi
						AND SM.IDStato <> @StatoAnnullato -- Non è ancora annullato
						AND SM.IDSTato in (select idstatosm from [dbo].[fnGetStatiSMIniziali]())				    
			*/ 
			   
			   SELECT 
						K4.CODICERICAMBIO, K4.CODICERETTIFICA, K4.CODICEMOTIVAZIONE,
						k4.LETTERAINCONVENIENTE, K4.RIGAPROGRESSIVA,
						sr.idsr, srd.IDSRDettaglio 
					FROM KWTA4 K4
					inner join KWTA2 K2 on k4.PARENTID = K2.ID
					inner join KWTA1 K1 on K2.PARENTID = K1.ID
					left join asr sr 
					       on sr.idsr = dbo.fnGetIdsrSIGI(k1.MERCATO,k1.MARCA, k1.ENTEEMITTENTE, k1.NUMEROSR, k1.DATAEMISSIONE)  -- <== Eventuale IDSR
					left join ASRDettaglio srd -- <== Eventuale IDSRDettaglio
					       on srd.[IDSR] = sr.[IDSR] AND  
						      srd.CodiceSpesa    = k2.CODICESPESA AND
							  srd.CodCodiceInput = k2.CODICEPEZZO AND
							  -- @@@ Lettera inconveniente e riga
							  srd.CodAnomalia	 = k2.CODICEANOMALIA AND
							  srd.LetteraInconveniente = k2.LETTERAINCONVENIENTE
					WHERE 
						K1.ID = @wta1GUID -- Sto analizzando il KWTA1 corrente			
						AND K4.CODICERETTIFICA = 'A0' -- Annullo Sigi
			
			OPEN Materiali_Annullati_Cursor
			
			FETCH NEXT FROM Materiali_Annullati_Cursor
			INTO  @ANN_CODICERICAMBIO, @ANN_CODICERETTIFICA, @ANN_CODICEMOTIVAZIONE, @ANN_LETTERAINCONVENIENTE,	@ANN_RIGAPROGRESSIVA,
				  @ANN_IDSR, @ANN_IDSRDETTAGLIO

			WHILE @@FETCH_STATUS = 0
			BEGIN
			    
				-- Verifico se il categorico è ripetuto più volte all'interno della stessa SR Dettaglio

				DECLARE @ContaCategorici int = 0 

				SELECT @ContaCategorici = count(*) 
				  FROM ASM 
				  WHERE CodCategorico = @ANN_CODICERICAMBIO
				    and IDSR = @ANN_IDSR 
					and IDSRDettaglio= @ANN_IDSRDETTAGLIO	

				If @ContaCategorici = 1 
					-- Se ne ho uno solo posso usare ASM
					BEGIN
						SELECT @ANN_IDSM = IDSM, @ANN_IDSTATOSM = IDStato
						  FROM ASM 
						 WHERE CodCategorico = @ANN_CODICERICAMBIO
						   AND IDSR = @ANN_IDSR
						   AND IDSRDettaglio = @ANN_IDSRDETTAGLIO
					END
				ELSE 
					-- Categorico ripetuto nella Sr Dettaglio, devo usare ASMExt con riga e posizione
					BEGIN
						SELECT @ANN_IDSM = SM.IDSM, @ANN_IDSTATOSM = SM.IDStato
						  FROM AsmExt ex 
						 INNER JOIN ASM SM on SM.idsm = ex.IDSM
						 WHERE ex.[CodCategorico] = dbo.fnIsNull(@ANN_CODICERICAMBIO) 
						   AND ex.IDSR = @ANN_IDSR
						   AND ex.[LetteraInconveniente] = @ANN_LETTERAINCONVENIENTE
						   AND ex.[RigaProgressiva]      = @ANN_RIGAPROGRESSIVA
					END

				--SET @Messaggio = ' Debug>>> Cursore Materiali_Annullati - @ANN_IDSR: ' + str(isnull(@ANN_IDSR,-1)) + ' @@ANN_IDSRDETTAGLIO: ' + str(isnull(@ANN_IDSRDETTAGLIO,-1))  + ' @ANN_IDSM: ' + str(isnull(@ANN_IDSM,-1)) + ' in stato: ' + str(isnull(@ANN_IDSTATOSM,0)) +  ' Categorico: ' + isnull(@ANN_CODICERICAMBIO,'-') + ' @ContaCategorici: ' + str(isnull(@ContaCategorici,0))  + ' Lettera inconveniente: ' + isnull(@ANN_LETTERAINCONVENIENTE,'-') + ' Riga progressiva: ' + isnull(@ANN_RIGAPROGRESSIVA,'-')
				--PRINT @Messaggio
				--If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

				-- Se la SM non è ancora annullata tento di forzare lo stato di annullo Sigi
				IF @ANN_IDSTATOSM <> @StatoAnnullato AND -- Non è ancora annullato
				   @ANN_IDSTATOSM in (select idstatosm from [dbo].[fnGetStatiSMIniziali]()) -- SM ancora in stato "iniziale" non preso in carico dal Dealer
					BEGIN
						SET @Messaggio = 'Annullo Sigi della SM: ' + str(isnull(@ANN_IDSM,0)) + ' in stato: ' + str(isnull(@ANN_IDSTATOSM,0)) + ' associata a IDSR : ' + str(isnull(@IdQuestaSR,0)) + ' Categorico: ' + isnull(@ANN_CODICERICAMBIO,'-') +  ' Lettera inconveniente: ' + isnull(@ANN_LETTERAINCONVENIENTE,'-') + ' Riga progressiva: ' + isnull(@ANN_RIGAPROGRESSIVA,'-')
						PRINT @Messaggio
						If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1

						UPDATE ASM SET IDStato = @StatoAnnullato, DataUpdate = getdate(), IDUserUpdate = 0 WHERE IDSM = @ANN_IDSM;
					END

				FETCH NEXT FROM Materiali_Annullati_Cursor
				INTO  @ANN_CODICERICAMBIO, @ANN_CODICERETTIFICA, @ANN_CODICEMOTIVAZIONE, @ANN_LETTERAINCONVENIENTE,	@ANN_RIGAPROGRESSIVA,
					  @ANN_IDSR, @ANN_IDSRDETTAGLIO

			END  -- Fine Loop cursore Materiali_Annullati_Cursor

			CLOSE Materiali_Annullati_Cursor
			DEALLOCATE Materiali_Annullati_Cursor

		-- CCB 20210427 -- Evolutiva SR Backlog -- Fine

		END -- Fine Begin ramo ELSE Esistenza SR (SR già esistente)
	
	Next_wta1:
	--	IF @last_error = 0
	--		COMMIT TRANSACTION wta1_insert

		FETCH NEXT FROM WTA1_Cursor
		INTO @wta1GUID, @StatoSR, @NUMEROSR, @MERCATO, @SOCIETA, @DIVISIONE, @DIREAZIONEAREA, @MARCA, @ENTEEMITTENTE, @CODICERIPARATORE, 
			@CODICEMVS, @DATAEMISSIONE, @TELAIO, @DATAINIZIOGARANZIA, @KMVETTURA, @DATAINTERVENTO, @NUMERORICEVUTAFISCALE, @DATARICEVUTAFISCALE, 
			@NUMEROCOMMESSA, @DATACHIUSURACOMMESSA, @DATACONTABILIZZAZIONE, @TOTALEOREMO, @SR_SEGNOIMPORTOMO, @SR_IMPORTOMO, @SR_SEGNOIMPORTOMATERIALI, 
			@SR_IMPORTOMATERIALI, @SEGNOIMPORTOTOTALESR, @IMPORTOTOTALESR, @DATAPRODUZIONEVEICOLO
	END -- END: Cursor on KWTA1

	CLOSE WTA1_Cursor
	DEALLOCATE WTA1_Cursor

	SET @Messaggio = ' === Fine esecuzione Import SR SIGI - Ora di completamento: '   + convert(varchar, getdate(), 126) + ' ==='
	PRINT @Messaggio
	If @ScriviLog = 1 EXEC [spKLogDetailsIns] @NomeSP, @Messaggio, 1


	-- CCB 20210427 -- Evolutiva SR Backlog
	--                 A fine loop SR scrivo nel log gli eventuali SM creati da SR con codice rettifica
	--                 da una lista univoca SM + Codici dalla tabella @SM_RETTIFICATI
			
	-- Debug Rettifiche SM

	/************** CCB 20210716 - Spostata insert nel nuovo loop cursore WTA4 per ogni IDSM

	IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'Z_debug_SM_RETTIFICATI')
		BEGIN
			select R.IDSM, R.CODICERETTIFICA, R.CODICEMOTIVAZIONE, getdate() as Data_Run 
				into Z_debug_SM_RETTIFICATI from @SM_RETTIFICATI R ;
		END
	ELSE
		BEGIN
			INSERT INTO Z_debug_SM_RETTIFICATI (IDSM, CODICERETTIFICA, CODICEMOTIVAZIONE, Data_Run)
			SELECT R.IDSM, R.CODICERETTIFICA, R.CODICEMOTIVAZIONE, getdate() as Data_Run 
				FROM @SM_RETTIFICATI  R
		END;

	With SMRettificatiUnivoci as 
		(select DISTINCT IDSM, CODICERETTIFICA, CODICEMOTIVAZIONE 
		from @SM_RETTIFICATI)
	INSERT INTO [dbo].[ASMRettifiche] (IDSM, CODICERETTIFICA, CODICEMOTIVAZIONE, [IDUserUpdate], [DataUpdate]) 
		SELECT SMR.IDSM, SMR.CODICERETTIFICA, SMR.CODICEMOTIVAZIONE, 0, getdate()
			FROM SMRettificatiUnivoci SMR

	-- CCB 20210427 -- Evolutiva SR Backlog -- Fine

   ************* CCB 20210716 - Fine commento inset ASmRettifiche */

END

ELSE

BEGIN 

	exec spKLogIns 'ImportSR', 'Import SR failed caused by errors in APPLYFILTERS procedure.', 0

END
GO
