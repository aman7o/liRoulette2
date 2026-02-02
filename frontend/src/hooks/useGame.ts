import { useState, useEffect, useCallback, useRef } from 'react';
import { useLinera } from '../contexts/LineraContext';

export interface Bet {
  playerChainId: string;
  playerName: string;
  betType: string;
  numbers: number[];
  amount: number;
}

export interface SpinResult {
  number: number;
  color: string;
  timestamp: string;
  winners: Array<{
    playerChainId: string;
    playerName: string;
    betType: string;
    betAmount: number;
    payout: number;
  }>;
  totalBetAmount?: number;
}

export interface GameState {
  isSpinning: boolean;
  currentBets: Bet[];
  lastResult: SpinResult | null;
  history: number[];
  bettingEndTime?: number | null; // Timestamp (ms) when betting ends - for syncing timer
}

export interface Player {
  chainId: string;
  name: string;
  balance: number;
}

export interface PlayerStats {
  totalWins: number;
  totalLosses: number;
  totalWinAmount: number;
  totalLossAmount: number;
  totalRounds: number;
  totalWagered: number;
  bestWin: number;
}

export function useGame() {
  const { queryHost, mutate, subscribe, isConnected, chainId, playerId, gameMode, isHost, hostedChainId, joinedChainId } = useLinera();
  const [gameState, setGameState] = useState<GameState>({
    isSpinning: false,
    currentBets: [],
    lastResult: null,
    history: [],
  });
  const [players, setPlayers] = useState<Player[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Local spinning state - controls UI animation independent of backend state
  const [isWheelSpinning, setIsWheelSpinning] = useState(false);
  const [pendingResult, setPendingResult] = useState<SpinResult | null>(null);
  const [showResultPopup, setShowResultPopup] = useState(false);

  // Stats tracking (stored in localStorage for persistence)
  const [playerStats, setPlayerStats] = useState<PlayerStats>({
    totalWins: 0,
    totalLosses: 0,
    totalWinAmount: 0,
    totalLossAmount: 0,
    totalRounds: 0,
    totalWagered: 0,
    bestWin: 0,
  });

  // Track bets placed before spin to calculate loss
  const betsBeforeSpinRef = useRef<Bet[]>([]);
  // Store pending players update until wheel animation completes
  const pendingPlayersRef = useRef<Player[] | null>(null);
  // Store pending history update until wheel animation completes
  const pendingHistoryRef = useRef<number[] | null>(null);
  // Track if wheel is spinning (ref for use in subscription callback)
  const isSpinningRef = useRef(false);
  // Track last known result timestamp to detect new spins (for joined players)
  const lastResultTimestampRef = useRef<string | null>(null);

  // Round management for multiplayer sync
  const [roundPhase, setRoundPhase] = useState<'waiting' | 'betting' | 'spinning'>('waiting');
  const [bettingTimeLeft, setBettingTimeLeft] = useState(0);
  const [bettingEndTime, setBettingEndTime] = useState<number | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    const activeChain = hostedChainId || joinedChainId;
    if (activeChain || gameMode === 'solo') {
      setGameState({
        isSpinning: false,
        currentBets: [],
        lastResult: null,
        history: [],
      });
      setPlayers([]);
      setRoundPhase('waiting');
      setBettingTimeLeft(0);
      setBettingEndTime(null);
      setIsWheelSpinning(false);
      setPendingResult(null);
      setShowResultPopup(false);
      lastResultTimestampRef.current = null;
      betsBeforeSpinRef.current = [];
    }
  }, [hostedChainId, joinedChainId, gameMode]);

  // Fetch game state from GraphQL (queries HOST chain for game state)
  const fetchGameState = useCallback(async () => {
    if (!isConnected) return;

    try {
      // Query HOST chain for game state (game state lives on host)
      const data = await queryHost(`
        query {
          gameState {
            isSpinning
            currentBets {
              playerChainId
              playerName
              betType
              numbers
              amount
            }
            lastResult {
              number
              color
              timestamp
              winners {
                playerChainId
                playerName
                betType
                betAmount
                payout
              }
            }
            history
          }
          players {
            chainId
            name
            balance
          }
        }
      `);

      setGameState(data.gameState);
      setPlayers(data.players);
    } catch (err) {
      console.error('[GAME] Failed to fetch game state:', err);
      setError(err instanceof Error ? err.message : 'Failed to fetch game state');
    }
  }, [queryHost, isConnected]);

  useEffect(() => {
    if (!isConnected) return;

    const unsubscribe = subscribe((event: any) => {
      if (isSpinningRef.current) return;
      fetchGameState();
    });

    fetchGameState();

    return unsubscribe;
  }, [isConnected, subscribe, fetchGameState]);

  useEffect(() => {
    if (!isConnected) return;
    if (isSpinningRef.current) return;

    const pollInterval = setInterval(async () => {
      try {
        if (isSpinningRef.current) return;
        await fetchGameState();
      } catch (err) {
        console.error('[POLL] Error refreshing game state:', err);
      }
    }, 2000);

    return () => clearInterval(pollInterval);
  }, [isConnected, fetchGameState]);

  useEffect(() => {
    if (!isConnected || gameMode !== 'join' || !playerId) return;

    const pollInterval = setInterval(async () => {
      if (isSpinningRef.current) return;

      try {
        const data = await queryHost(`
          query {
            gameState {
              currentBets { playerChainId amount }
              bettingEndTime
              lastResult {
                number
                color
                timestamp
                winners {
                  playerChainId
                  playerName
                  betType
                  betAmount
                  payout
                }
              }
            }
            players {
              chainId
              name
              balance
            }
          }
        `);

        const currentTimestamp = data.gameState.lastResult?.timestamp || null;

        if (currentTimestamp && currentTimestamp !== lastResultTimestampRef.current && !isWheelSpinning) {
          const shouldTriggerWheel = lastResultTimestampRef.current !== null || roundPhase === 'betting';

          if (shouldTriggerWheel) {
            if (timerRef.current) {
              clearInterval(timerRef.current);
              timerRef.current = null;
            }
            setBettingTimeLeft(0);

            const myBets = betsBeforeSpinRef.current.filter(b => b.playerChainId === playerId);
            const myTotalBet = myBets.reduce((sum, b) => sum + b.amount, 0);

            const resultWithBets = {
              ...data.gameState.lastResult,
              totalBetAmount: myTotalBet,
            };
            setPendingResult(resultWithBets);
            pendingPlayersRef.current = data.players;

            setRoundPhase('spinning');
            setIsWheelSpinning(true);
            isSpinningRef.current = true;
          }

          lastResultTimestampRef.current = currentTimestamp;
        }

        if (!currentTimestamp && lastResultTimestampRef.current === null) {
          lastResultTimestampRef.current = '';
        }

        if (data.gameState.bettingEndTime) {
          const now = Date.now();
          const remaining = Math.max(0, Math.ceil((data.gameState.bettingEndTime - now) / 1000));

          if (remaining > 0) {
            if (roundPhase !== 'betting') {
              setRoundPhase('betting');
            }
            setBettingTimeLeft(remaining);
          }
        } else if (data.gameState.currentBets.length > 0 && roundPhase === 'waiting') {
          setRoundPhase('betting');
        }

        if (data.gameState.currentBets.length > 0) {
          betsBeforeSpinRef.current = [...data.gameState.currentBets];
        }
      } catch (err) {
        console.error('[SYNC] Polling error:', err);
      }
    }, 1000);

    return () => clearInterval(pollInterval);
  }, [isConnected, gameMode, isWheelSpinning, roundPhase, queryHost, playerId]);

  useEffect(() => {
    if (playerId) {
      const saved = localStorage.getItem(`roulette_stats_${playerId}`);
      if (saved) {
        const parsed = JSON.parse(saved);
        setPlayerStats({
          totalWins: parsed.totalWins || 0,
          totalLosses: parsed.totalLosses || 0,
          totalWinAmount: parsed.totalWinAmount || 0,
          totalLossAmount: parsed.totalLossAmount || 0,
          totalRounds: parsed.totalRounds || 0,
          totalWagered: parsed.totalWagered || 0,
          bestWin: parsed.bestWin || 0,
        });
      } else {
        setPlayerStats({ totalWins: 0, totalLosses: 0, totalWinAmount: 0, totalLossAmount: 0, totalRounds: 0, totalWagered: 0, bestWin: 0 });
      }
    }
  }, [playerId]);

  useEffect(() => {
    if (playerId) {
      localStorage.setItem(`roulette_stats_${playerId}`, JSON.stringify(playerStats));
    }
  }, [playerStats, playerId]);

  const registerPlayer = useCallback(
    async (name: string, initialBalance: number) => {
      setIsLoading(true);
      setError(null);

      try {
        await mutate(`
          mutation RegisterPlayer($playerId: String!, $name: String!, $initialBalance: Int!) {
            registerPlayer(playerId: $playerId, name: $name, initialBalance: $initialBalance)
          }
        `, { playerId, name, initialBalance });

        await fetchGameState();
      } catch (err) {
        console.error('[GAME] Failed to register player:', err);
        setError(err instanceof Error ? err.message : 'Failed to register');
      } finally {
        setIsLoading(false);
      }
    },
    [mutate, fetchGameState, playerId]
  );

  const placeBet = useCallback(
    async (betType: string, numbers: number[], amount: number) => {
      setIsLoading(true);
      setError(null);

      try {
        await mutate(`
          mutation PlaceBet($playerId: String!, $betType: BetType!, $numbers: [Int!]!, $amount: Int!) {
            placeBet(playerId: $playerId, betType: $betType, numbers: $numbers, amount: $amount)
          }
        `, { playerId, betType, numbers, amount });

        await fetchGameState();
      } catch (err) {
        console.error('[GAME] Failed to place bet:', err);
        setError(err instanceof Error ? err.message : 'Failed to place bet');
      } finally {
        setIsLoading(false);
      }
    },
    [mutate, fetchGameState, playerId]
  );

  const spinWheel = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    setShowResultPopup(false);

    betsBeforeSpinRef.current = [...gameState.currentBets];
    const totalBetAmount = gameState.currentBets
      .filter(bet => bet.playerChainId === playerId)
      .reduce((sum, bet) => sum + bet.amount, 0);

    try {
      setIsWheelSpinning(true);
      isSpinningRef.current = true;

      await mutate(`
        mutation {
          spinWheel
        }
      `);

      const data = await queryHost(`
        query {
          gameState {
            isSpinning
            currentBets {
              playerChainId
              playerName
              betType
              numbers
              amount
            }
            lastResult {
              number
              color
              timestamp
              winners {
                playerChainId
                playerName
                betType
                betAmount
                payout
              }
            }
            history
          }
          players {
            chainId
            name
            balance
          }
        }
      `);

      const result = data.gameState.lastResult;
      if (result) {
        result.totalBetAmount = totalBetAmount;
      }
      setPendingResult(result);

      pendingPlayersRef.current = data.players;
      pendingHistoryRef.current = data.gameState.history;

      setGameState(prev => ({
        ...prev,
        currentBets: [],
      }));

    } catch (err) {
      console.error('[GAME] Failed to spin wheel:', err);
      setError(err instanceof Error ? err.message : 'Failed to spin wheel');
      setIsWheelSpinning(false);
      isSpinningRef.current = false;
    } finally {
      setIsLoading(false);
    }
  }, [mutate, queryHost, gameState.currentBets, playerId]);

  const startRound = useCallback(async () => {
    if (roundPhase !== 'waiting') return;
    if (!isHost) return;

    try {
      await mutate(`mutation { startRound }`);
    } catch (err) {
      console.error('[startRound] Failed to call startRound mutation:', err);
    }

    const endTime = Date.now() + 30000;
    setBettingEndTime(endTime);
    setRoundPhase('betting');
    setBettingTimeLeft(30);

    if (timerRef.current) clearInterval(timerRef.current);

    timerRef.current = setInterval(() => {
      const remaining = Math.ceil((endTime - Date.now()) / 1000);
      if (remaining <= 0) {
        if (timerRef.current) clearInterval(timerRef.current);
        timerRef.current = null;
        setBettingEndTime(null);
        setBettingTimeLeft(0);
        setRoundPhase('spinning');
        spinWheel();
      } else {
        setBettingTimeLeft(remaining);
      }
    }, 1000);
  }, [roundPhase, isHost, spinWheel, mutate]);

  // Recalculate timer when tab becomes visible (fixes background tab throttling)
  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible' && bettingEndTime) {
        const remaining = Math.ceil((bettingEndTime - Date.now()) / 1000);
        if (remaining > 0) {
          setBettingTimeLeft(remaining);
        } else if (roundPhase === 'betting') {
          // Timer expired while tab was hidden
          setBettingTimeLeft(0);
          setBettingEndTime(null);
          if (isHost) {
            setRoundPhase('spinning');
            spinWheel();
          }
        }
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange);
  }, [bettingEndTime, roundPhase, isHost, spinWheel]);

  const onWheelAnimationComplete = useCallback(() => {
    setIsWheelSpinning(false);

    if (pendingPlayersRef.current) {
      setPlayers(pendingPlayersRef.current);
      pendingPlayersRef.current = null;
    }

    if (pendingHistoryRef.current) {
      setGameState(prev => ({
        ...prev,
        history: pendingHistoryRef.current!,
      }));
      pendingHistoryRef.current = null;
    }

    if (pendingResult) {
      setGameState(prev => ({
        ...prev,
        lastResult: pendingResult,
        isSpinning: false,
      }));

      const myWin = pendingResult.winners.find(w => w.playerChainId === playerId);
      const totalBetAmount = pendingResult.totalBetAmount || 0;

      if (totalBetAmount > 0) {
        if (myWin) {
          const netProfit = myWin.payout;
          setPlayerStats(prev => ({
            ...prev,
            totalWins: prev.totalWins + 1,
            totalWinAmount: prev.totalWinAmount + netProfit,
            totalRounds: prev.totalRounds + 1,
            totalWagered: prev.totalWagered + totalBetAmount,
            bestWin: Math.max(prev.bestWin, netProfit),
          }));
        } else {
          setPlayerStats(prev => ({
            ...prev,
            totalLosses: prev.totalLosses + 1,
            totalLossAmount: prev.totalLossAmount + totalBetAmount,
            totalRounds: prev.totalRounds + 1,
            totalWagered: prev.totalWagered + totalBetAmount,
          }));
        }
      }

      setShowResultPopup(true);
    }

    isSpinningRef.current = false;
    setRoundPhase('waiting');
  }, [pendingResult, playerId]);

  const dismissResultPopup = useCallback(() => {
    setShowResultPopup(false);
    setPendingResult(null);
    fetchGameState();
  }, [fetchGameState]);

  const currentPlayer = players.find((p) => p.chainId === playerId) || null;

  return {
    gameState,
    players,
    currentPlayer,
    isLoading,
    error,
    registerPlayer,
    placeBet,
    spinWheel,
    fetchGameState,
    // New exports for proper animation timing
    isWheelSpinning,
    pendingResult,
    showResultPopup,
    onWheelAnimationComplete,
    dismissResultPopup,
    playerStats,
    // Multiplayer sync exports
    roundPhase,
    bettingTimeLeft,
    startRound,
  };
}
